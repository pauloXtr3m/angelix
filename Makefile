DEFAULT_MODULES = llvm-gcc llvm2 minisat stp klee-uclibc klee z3 clang bear runtime frontend maxsmt synthesis
OPTIONAL_MODULES = nsynth semfix
CLEAN_MODULES = $(addprefix clean-, $(DEFAULT_MODULES)) $(addprefix clean-, $(OPTIONAL_MODULES))

help:
	@echo ~~~~~~~~~~~~~~~~~~ Angelix ~~~~~~~~~~~~~~~~~~
	@echo Semantics-based Automated Program Repair Tool
	@echo
	@echo \'make default\''          'build default modules
	@echo \'make all\''                  'build all modules
	@echo \'make MODULE\''                    'build module
	@echo \'make test\''                         'run tests
	@echo \'make test-semfix\''           'run semfix tests
	@echo \'make docker\''              'build docker image
	@echo
	@echo Default modules:
	@echo -n ' '$(foreach module, $(DEFAULT_MODULES),"* $(module)\n")
	@echo
	@echo Optional modules:
	@echo -n ' '$(foreach module, $(OPTIONAL_MODULES),"* $(module)\n")

default: $(DEFAULT_MODULES)
all: $(DEFAULT_MODULES) $(OPTIONAL_MODULES)

.PHONY: help all $(DEFAULT_MODULES) $(OPTIONAL_MODULES) test test-semfix docker

# Information for retrieving dependencies

DOWNLOAD=wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 --tries=5 --continue

LLVM_GCC_URL=http://llvm.org/releases/2.9/llvm-gcc4.2-2.9-x86_64-linux.tar.bz2
LLVM_GCC_ARCHIVE=llvm-gcc4.2-2.9-x86_64-linux.tar.bz2
LLVM2_PATCH_URL=http://www.mail-archive.com/klee-dev@imperial.ac.uk/msg01302/unistd-llvm-2.9-jit.patch
LLVM2_PATCH=unistd-llvm-2.9-jit.patch
LLVM2_URL=http://llvm.org/releases/2.9/llvm-2.9.tgz
LLVM2_ARCHIVE=llvm-2.9.tgz
LLVM3_URL=http://llvm.org/releases/3.7.0/llvm-3.7.0.src.tar.xz
LLVM3_ARCHIVE=llvm-3.7.0.src.tar.xz
CLANG_URL=http://llvm.org/releases/3.7.0/cfe-3.7.0.src.tar.xz
CLANG_ARCHIVE=cfe-3.7.0.src.tar.xz
CLANG_TOOLS_EXTRA_URL=http://llvm.org/git/clang-tools-extra.git
COMPILER_RT_URL=http://llvm.org/releases/3.7.0/compiler-rt-3.7.0.src.tar.xz
COMPILER_RT_ARCHIVE=compiler-rt-3.7.0.src.tar.xz
CLANG_TOOLS_EXTRA_URL=http://llvm.org/git/clang-tools-extra.git
STP_URL=https://github.com/stp/stp.git
MINISAT_URL=https://github.com/niklasso/minisat.git
Z3_URL=https://github.com/mechtaev/z3.git
Z3_2_19_URL=http://research.microsoft.com/en-us/um/redmond/projects/z3/z3-2.19.tar.gz
Z3_2_19_ARCHIVE=z3-2.19.tar.gz
KLEE_UCLIBC_URL=https://github.com/klee/klee-uclibc.git
BEAR_URL=https://github.com/rizsotto/Bear.git
MAXSMT_URL=https://github.com/mechtaev/maxsmt-playground.git
LOCAL_LIB_URL=http://search.cpan.org/CPAN/authors/id/H/HA/HAARG/local-lib-2.000018.tar.gz
LOCAL_LIB_ARCHIVE=local-lib-2.000018.tar.gz

# Testing #

test:
	python3 tests/tests.py

test-semfix:
	python3 tests/semfix-tests.py

# LLVM-GCC #

llvm-gcc: build/$(LLVM_GCC_ARCHIVE)
	cd build && tar xf $(LLVM_GCC_ARCHIVE)

build/$(LLVM_GCC_ARCHIVE):
	cd build && $(DOWNLOAD) $(LLVM_GCC_URL)

# LLVM2 #

llvm2: build/$(LLVM2_ARCHIVE) build/$(LLVM2_PATCH)
	cd build && tar xf $(LLVM2_ARCHIVE)
	cd build && patch -p0 < $(LLVM2_PATCH)
	cd $(LLVM2_DIR) && ./configure --enable-optimized --enable-assertions && make

#	cd $(LLVM2_DIR) && ./configure --disable-optimized --enable-debug-runtime --enable-assertions && make

build/$(LLVM2_ARCHIVE):
	cd build && $(DOWNLOAD) $(LLVM2_URL)

build/$(LLVM2_PATCH):
	cd build && $(DOWNLOAD) $(LLVM2_PATCH_URL)

# STP #

stp: $(STP_DIR)
	cd $(STP_DIR) && mkdir -p build && cd build && cmake -DMINISAT_LIBRARY="$(MINISAT_DIR)/build/libminisat.so.2" -DMINISAT_INCLUDE_DIR="$(MINISAT_DIR)" -G 'Unix Makefiles' $(STP_DIR) && make

$(STP_DIR):
	cd build && git clone --depth=1 $(STP_URL)

# MINISAT #

minisat: $(MINISAT_DIR)
	cd $(MINISAT_DIR) && mkdir -p build && cd build && cmake -G 'Unix Makefiles' $(MINISAT_DIR) && make

$(MINISAT_DIR):
	cd build && git clone --depth=1 $(MINISAT_URL)

# KLEE-UCLIBC #

klee-uclibc: $(KLEE_UCLIBC_DIR)
	cd $(KLEE_UCLIBC_DIR) && ./configure --make-llvm-lib && make -j2

$(KLEE_UCLIBC_DIR):
	cd build && git clone --depth=1 $(KLEE_UCLIBC_URL)

# KLEE #

klee:
	cd $(KLEE_DIR) && ./configure --with-llvm=$(LLVM2_DIR) --with-stp=$(STP_DIR)/build --with-z3=$(Z3_INSTALL_DIR) --with-uclibc=$(KLEE_UCLIBC_DIR) --enable-posix-runtime && make ENABLE_OPTIMIZED=1
	cp $(KLEE_DIR)/Release+Asserts/lib/libkleeRuntest.so $(KLEE_DIR)/Release+Asserts/lib/libkleeRuntest.so.1.0


# cd $(KLEE_DIR) && CXXFLAGS="-g -O0" CFLAGS="-g -O0" ./configure --with-llvm=$(LLVM2_DIR) --with-stp=$(STP_DIR)/build --with-z3=$(Z3_INSTALL_DIR) --with-uclibc=$(KLEE_UCLIBC_DIR) --disable-optimized --enable-posix-runtime --with-runtime=Debug+Asserts && make
# cp $(KLEE_DIR)/Debug+Asserts/lib/libkleeRuntest.so $(KLEE_DIR)/Debug+Asserts/lib/libkleeRuntest.so.1.0

# Angelix runtime #

runtime:
	cd src/runtime && make
	mkdir -p $(ANGELIX_ROOT)/build/lib/klee
	mkdir -p $(ANGELIX_ROOT)/build/lib/test
	cp src/runtime/libangelix.test.a $(ANGELIX_ROOT)/build/lib/test/libangelix.a
	cp src/runtime/libangelix.klee.a $(ANGELIX_ROOT)/build/lib/klee/libangelix.a
	cd src/runtime && make clean

# Z3 #

z3: $(Z3_DIR)
	cd $(Z3_DIR) && python scripts/mk_make.py --java --prefix=$(Z3_INSTALL_DIR) && cd build && make && make install

$(Z3_DIR):
	cd build && git clone --depth=1 $(Z3_URL)

# Z3_2 #

z3_2: $(Z3_2_19_DIR)/bin/z3_semfix

$(Z3_2_19_DIR)/bin/z3_semfix: build/$(Z3_2_19_ARCHIVE)
	cd build && mkdir -p z3_tmp && tar xzf $(Z3_2_19_ARCHIVE) --directory z3_tmp \
	&& rm -rf $(Z3_2_19_DIR) && mv -f z3_tmp/z3 $(Z3_2_19_DIR) && rm -rf z3_tmp \
	&& mv $(Z3_2_19_DIR)/bin/z3 $(Z3_2_19_DIR)/bin/z3_semfix

build/$(Z3_2_19_ARCHIVE):
	cd build && $(DOWNLOAD) $(Z3_2_19_URL)

# local::lib
build/local-lib-2.000018/installed: build/$(LOCAL_LIB_ARCHIVE) $(LOCAL_PERL_ROOT)
	cd build && tar xzf $(LOCAL_LIB_ARCHIVE) \
	&& cd local-lib-2.000018 && perl Makefile.PL --bootstrap=$(LOCAL_PERL_ROOT) --no-manpages \
	&& make test && make install && touch installed

local_lib: build/local-lib-2.000018/installed

$(LOCAL_PERL_ROOT):
	mkdir -p $(LOCAL_PERL_ROOT)

build/$(LOCAL_LIB_ARCHIVE):
	cd build && $(DOWNLOAD) $(LOCAL_LIB_URL)

# semfix #

semfix: local_lib z3_2
	perl -MCPAN -Mlocal::lib=${LOCAL_PERL_ROOT} -e 'CPAN::install(Log::Log4perl)' \
	&& perl -MCPAN -Mlocal::lib=${LOCAL_PERL_ROOT} -e 'CPAN::install(XML::Simple)'

# MAX-SAT #

maxsmt: $(MAXSMT_DIR)
	mkdir -p $(MAXSMT_DIR)/lib
	cp $(Z3_JAR) $(MAXSMT_DIR)/lib/
	mkdir -p $(MAXSMT_DIR)/log
	cd $(MAXSMT_DIR) && sbt package

$(MAXSMT_DIR):
	cd build && git clone --depth=1 $(MAXSMT_URL)

# Synthesis #

synthesis:
	mkdir -p $(SYNTHESIS_DIR)/lib
	cp $(MAXSMT_JAR) $(SYNTHESIS_DIR)/lib/
	cp $(Z3_JAR) $(SYNTHESIS_DIR)/lib/
	mkdir -p $(SYNTHESIS_DIR)/log
	cd $(SYNTHESIS_DIR) && sbt assembly

# Synthesis #

nsynth:
	mvn install:install-file -Dfile=$(Z3_JAR) -DgroupId=com.microsoft.z3 -DartifactId=z3 -Dversion=4 -Dpackaging=jar
	cd $(ANGELIX_ROOT)/src/nsynth && mvn package

# Clang #

clang: build/$(LLVM3_ARCHIVE) build/$(CLANG_ARCHIVE) build/$(COMPILER_RT_ARCHIVE)
	cd build && tar xf $(LLVM3_ARCHIVE)
	mkdir -p "$(LLVM3_DIR)/tools/clang"
	cd build && tar xf $(CLANG_ARCHIVE) --directory "$(LLVM3_DIR)/tools/clang" --strip-components=1
	mkdir -p "$(LLVM3_DIR)/projects/compiler-rt"
	cd build && tar xf $(COMPILER_RT_ARCHIVE) --directory "$(LLVM3_DIR)/projects/compiler-rt" --strip-components=1
	cd "$(LLVM3_DIR)/tools/clang/tools/" && git clone --branch release_37 $(CLANG_TOOLS_EXTRA_URL) extra
	mkdir -p "$(LLVM3_DIR)/build" && cd "$(LLVM3_DIR)/build" && cmake -G "Unix Makefiles" ../ && make

build/$(LLVM3_ARCHIVE):
	cd build && $(DOWNLOAD) $(LLVM3_URL)

build/$(CLANG_ARCHIVE):
	cd build && $(DOWNLOAD) $(CLANG_URL)

build/$(COMPILER_RT_ARCHIVE):
	cd build && $(DOWNLOAD) $(COMPILER_RT_URL)

# Frontend #

frontend: $(LLVM3_DIR)/tools/clang/tools/angelix
	grep -q angelix "$(LLVM3_DIR)/tools/clang/tools/CMakeLists.txt" || echo 'add_subdirectory(angelix)' >> "$(LLVM3_DIR)/tools/clang/tools/CMakeLists.txt"
	cd "$(LLVM3_DIR)/build" && make
	mkdir -p "$(LLVM3_DIR)/build/bin/angelix"
	cp "$(LLVM3_DIR)/build/bin/instrument-repairable" "$(ANGELIX_ROOT)/build/bin"
	cp "$(LLVM3_DIR)/build/bin/instrument-suspicious" "$(ANGELIX_ROOT)/build/bin"
	cp "$(LLVM3_DIR)/build/bin/apply-patch" "$(ANGELIX_ROOT)/build/bin"
	cp -r "$(LLVM3_DIR)/build/lib/clang/3.7.0/include/"* "$(ANGELIX_ROOT)/build/include"

$(LLVM3_DIR)/tools/clang/tools/angelix:
	ln -f -s "$(ANGELIX_ROOT)/src/frontend" "$(LLVM3_DIR)/tools/clang/tools/angelix"

# Bear #

bear: $(BEAR_DIR)
	cd "$(BEAR_DIR)" && mkdir -p build && cd build && cmake ../ && make all
	sed -i 's/exit_code = subprocess.call(args.build, env=environment)/exit_code = subprocess.call(args.build, env=environment, shell=True)/' "$(BEAR_DIR)/build/bear/bear"

$(BEAR_DIR):
	cd build && git clone --depth=1 $(BEAR_URL)

# Docker #

docker:
	docker build -t angelix .
