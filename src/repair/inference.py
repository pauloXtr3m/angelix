from os.path import join, dirname, relpath, basename
from utils import cd
import subprocess
import logging
from glob import glob
import os
from pprint import pprint

import z3
from z3 import Select, Concat, Array, BitVecSort, BitVecVal, Solver, BitVec


logger = logging.getLogger(__name__)


class InferenceError(Exception):
    pass


# Temporary solution to implement get_vars. In principle, it should be available in z3util.py
class AstRefKey:
    def __init__(self, n):
        self.n = n
    def __hash__(self):
        return self.n.hash()
    def __eq__(self, other):
        return self.n.eq(other.n)
    def __repr__(self):
        return str(self.n)

def askey(n):
    assert isinstance(n, z3.AstRef)
    return AstRefKey(n)

def get_vars(f):
    r = set()
    def collect(f):
      if z3.is_const(f): 
          if f.decl().kind() == z3.Z3_OP_UNINTERPRETED and not askey(f) in r:
              r.add(askey(f))
      else:
          for c in f.children():
              collect(c)
    collect(f)
    return r
# end


def parse_variables(vars):
    '''
    <type> ! suspicious ! <line> ! <column> ! <line> ! <column> ! <instance> ! angelic
    <type> ! suspicious ! <line> ! <column> ! <line> ! <column> ! <instance> ! original
    <type> ! suspicious ! <line> ! <column> ! <line> ! <column> ! <instance> ! env ! <name>
    <type> ! output ! <name> ! <instance>
    reachable ! <name> ! <instance>

    returns outputs, suspicious

    outputs: name -> type * num of instances
    suspicious: expr -> type * num of instances * env-name list
    reachable: set of strings
    
    Note: assume environment variables are always int
    '''
    output_type = dict()
    output_instances = dict()
    suspicious_type = dict()
    suspicious_instances = dict()
    suspicious_env = dict()
    reachable = set()
    for v in vars:
        tokens = v.split('!')
        first = tokens.pop(0)
        if first == 'reachable':
            label = tokens.pop(0)
            reachable.add(label)
        else:
            type = first
            kind = tokens.pop(0)
            if kind == 'output':
                name, instance = tokens.pop(0), int(tokens.pop(0))
                output_type[name] = type
                if name not in output_instances:
                    output_instances[name] = []
                output_instances[name].append(instance)
            elif kind == 'suspicious':
                expr = int(tokens.pop(0)), int(tokens.pop(0)), int(tokens.pop(0)), int(tokens.pop(0))
                instance = int(tokens.pop(0))
                value = tokens.pop(0)
                if value == 'angelic':
                    suspicious_type[expr] = type
                    if expr not in suspicious_instances:
                        suspicious_instances[expr] = []
                    suspicious_instances[expr].append(instance)
                elif value == 'original':
                    pass
                elif value == 'env':
                    name = tokens.pop(0)
                    if expr not in suspicious_env:
                        suspicious_env[expr] = set()
                    suspicious_env[expr].add(name)
                else:
                    raise InferenceError()
            else:
                raise InferenceError()

    outputs = dict()
    for name, type in output_type.items():
        for i in range(0, len(output_instances[name])):
            if i not in output_instances[name]:
                logger.error('inconsistent variables')
                raise InferenceError()
        outputs[name] = (type, len(output_instances[name]))

    suspicious = dict()
    for expr, type in suspicious_type.items():
        for i in range(0, len(suspicious_instances[expr])):
            if i not in suspicious_instances[expr]:
                logger.error('inconsistent variables')
                raise InferenceError()
        suspicious[expr] = (type, len(suspicious_instances[expr]), list(suspicious_env[expr]))

    return outputs, suspicious, reachable


class Inferrer:

    def __init__(self, config, tester):
        self.config = config
        self.run_test = tester

    def __call__(self, project, test, dump):
        logger.info('infering specification for test \'{}\''.format(test))

        environment = dict(os.environ)
        environment['ANGELIX_KLEE_MAX_FORKS'] = str(self.config['klee_max_forks'])
        environment['ANGELIX_KLEE_MAX_TIME'] = str(self.config['klee_timeout'])
        environment['ANGELIX_KLEE_MAX_SOLVER_TIME'] = str(self.config['klee_solver_timeout'])
        environment['ANGELIX_KLEE_WORKDIR'] = project.dir

        self.run_test(project, test, klee=True, env=environment)

        smt_glob = join(project.dir, 'klee-out-0', '*.smt2')
        smt_files = glob(smt_glob)

        # loading dump

        # name -> value list
        oracle = dict()

        vars = os.listdir(dump)
        for var in vars:
            instances = os.listdir(join(dump, var))
            for i in range(0, len(instances)):
                if str(i) not in instances:
                    logger.error('corrupted dump for test \'{}\''.format(test))
                    raise InferenceError()
            oracle[var] = []
            for i in range(0, len(instances)):
                file = join(dump, var, str(i))
                with open(file) as f:
                    content = f.read()
                oracle[var].append(content)

        # solving path constraints

        angelic_paths = []

        solver = Solver()

        for smt in smt_files:
            logger.info('solving path {}'.format(relpath(smt)))

            path = z3.parse_smt2_file(smt)

            variables = [str(var) for var in get_vars(path)
                         if str(var).startswith('int!')
                         or str(var).startswith('bool!')
                         or str(var).startswith('char!')
                         or str(var).startswith('reachable!')]

            outputs, suspicious, reachable = parse_variables(variables)

            # name -> value list (parsed)
            oracle_constraints = dict()

            def str_to_int(s):
                return int(s)

            def str_to_bool(s):
                if s == 'false':
                    return False
                if s == 'true':
                    return True
                raise InferenceError()

            def str_to_char(s):
                if len(s) != 1:
                    raise InferenceError()
                return s[0]
    
            dump_parser_by_type = dict()
            dump_parser_by_type['int'] = str_to_int
            dump_parser_by_type['bool'] = str_to_bool
            dump_parser_by_type['char'] = str_to_char

            def bool_to_bv32(b):
                if b:
                    return BitVecVal(1, 32)
                else:
                    return BitVecVal(0, 32)

            def int_to_bv32(i):
                return BitVecVal(i, 32)

            to_bv32_converter_by_type = dict()
            to_bv32_converter_by_type['bool'] = bool_to_bv32
            to_bv32_converter_by_type['int'] = int_to_bv32

            def bv32_to_bool(bv):
                return bv.as_long() != 0

            def bv32_to_int(bv):
                l = bv.as_long()
                if l >> 31 == 1:  # negative
                    l -= 4294967296
                return l

            from_bv32_converter_by_type = dict()
            from_bv32_converter_by_type['bool'] = bv32_to_bool
            from_bv32_converter_by_type['int'] = bv32_to_int

            matching_path = True

            if 'reachable' not in oracle and len(reachable) > 0:
                logger.info('labels \'{}\' executed while no executions required'.format(
                    list(reachable)))
                continue
            
            for expected_variable, expected_values in oracle.items():
                if expected_variable == 'reachable':
                    expected_reachable = set(expected_values)
                    if not (expected_reachable == reachable):
                        logger.info('labels \'{}\' executed while {} required'.format(
                            list(reachable),
                            list(expected_reachable)))
                        matching_path = False
                        break
                    continue
                if expected_variable not in outputs.keys():
                    outputs[expected_variable] = (None, 0)  # unconstraint does not mean wrong
                required_executions = len(expected_values)
                actual_executions = outputs[expected_variable][1]
                if required_executions != actual_executions:
                    logger.info('value \'{}\' executed {} times while {} required'.format(
                        expected_variable,
                        actual_executions,
                        required_executions))
                    matching_path = False
                    break
                oracle_constraints[expected_variable] = []
                for i in range(0, required_executions):
                    type = outputs[expected_variable][0]
                    try:
                        value = dump_parser_by_type[type](expected_values[i])
                    except:
                        logger.error('variable \'{}\' has incompatible type {}'.format(expected_variable,
                                                                                       type))
                        raise InferenceError()
                    oracle_constraints[expected_variable].append(value)

            if not matching_path:
                continue        

            solver.reset()
            solver.add(path)

            def array_to_bv32(array):
                return Concat(Select(array, BitVecVal(3, 32)),
                              Select(array, BitVecVal(2, 32)),
                              Select(array, BitVecVal(1, 32)),
                              Select(array, BitVecVal(0, 32)))

            def angelic_variable(type, expr, instance):
                pattern = '{}!suspicious!{}!{}!{}!{}!{}!angelic'
                s = pattern.format(type, expr[0], expr[1], expr[2], expr[3], instance)
                return Array(s, BitVecSort(32), BitVecSort(8))
        
            def original_variable(type, expr, instance):
                pattern = '{}!suspicious!{}!{}!{}!{}!{}!original'
                s = pattern.format(type, expr[0], expr[1], expr[2], expr[3], instance)
                return Array(s, BitVecSort(32), BitVecSort(8))

            def env_variable(expr, instance, name):
                pattern = 'int!suspicious!{}!{}!{}!{}!{}!env!{}'
                s = pattern.format(expr[0], expr[1], expr[2], expr[3], instance, name)
                return Array(s, BitVecSort(32), BitVecSort(8))

            def output_variable(type, name, instance):
                s = '{}!output!{}!{}'.format(type, name, instance)
                return Array(s, BitVecSort(32), BitVecSort(8))

            def angelic_selector(expr, instance):
                s = 'angelic!{}!{}!{}!{}!{}'.format(expr[0], expr[1], expr[2], expr[3], instance)
                return BitVec(s, 32)

            def original_selector(expr, instance):
                s = 'original!{}!{}!{}!{}!{}'.format(expr[0], expr[1], expr[2], expr[3], instance)
                return BitVec(s, 32)

            def env_selector(expr, instance, name):
                s = 'env!{}!{}!{}!{}!{}!{}'.format(name, expr[0], expr[1], expr[2], expr[3], instance)
                return BitVec(s, 32)

            for name, values in oracle_constraints.items():
                type, _ = outputs[name]
                for i, value in enumerate(values):
                    array = output_variable(type, name, i)
                    bv_value = to_bv32_converter_by_type[type](value)
                    solver.add(bv_value == array_to_bv32(array))

            for (expr, item) in suspicious.items():
                type, instances, env = item
                for instance in range(0, instances):
                    selector = angelic_selector(expr, instance)
                    array = angelic_variable(type, expr, instance)
                    solver.add(selector == array_to_bv32(array))

                    selector = original_selector(expr, instance)
                    array = original_variable(type, expr, instance)
                    solver.add(selector == array_to_bv32(array))

                    for name in env:
                        selector = env_selector(expr, instance, name)
                        array = env_variable(expr, instance, name)
                        solver.add(selector == array_to_bv32(array))
                        
            
            result = solver.check()
            if result != z3.sat:
                logger.info('UNSAT')
                continue
            model = solver.model()

            angelic_path = dict()

            for (expr, item) in suspicious.items():
                angelic_path[expr] = []
                type, instances, env = item
                for instance in range(0, instances):
                    bv_angelic = model[angelic_selector(expr, instance)]
                    angelic = from_bv32_converter_by_type[type](bv_angelic)
                    bv_original = model[original_selector(expr, instance)]
                    original = from_bv32_converter_by_type[type](bv_original)
                    logger.info('expression {}[{}]: angelic = {}, original = {}'.format(expr, instance, angelic, original))
                    env_values = dict()
                    for name in env:
                        bv_env = model[env_selector(expr, instance, name)]
                        value = from_bv32_converter_by_type['int'](bv_env)
                        env_values[name] = value

                    angelic_path[expr].append((angelic, original, env_values))

            angelic_paths.append(angelic_path)

        logger.info('found {} angelic paths for test \'{}\''.format(len(angelic_paths), test))
        return angelic_paths
