#!/bin/bash
# ==============================================================================
# Setup and Build Script for Minimal_Cell_4DWCM Bioinformatic Pipeline
# ==============================================================================
# This script sets up all required dependencies locally inside this folder:
# Conda environment: ./py/
# Build software:   ./software/
#
# Fully adaptive for all systems, automatically detecting GPU compute capabilities
# and host GCC compatibility to compile LAMMPS, Lattice Microbes, etc.
# ==============================================================================

set -e # Exit immediately on error

echo ">>> Creating software directory..."
mkdir -p software
cd software
SOFT_DIR=$(pwd)

echo ">>> Cloning repositories..."

# 1. Lattice_Microbes (Cloned first to get lm_precomp.yml)
if [ ! -d "Lattice_Microbes" ]; then
    echo "Cloning Lattice_Microbes..."
    git clone https://github.com/Luthey-Schulten-Lab/Lattice_Microbes.git
    echo "Applying Lattice_Microbes fixes..."
    cd Lattice_Microbes
    cat << 'EOF' > lm_build_fixes.patch
diff --git a/lm_precomp.yml b/lm_precomp.yml
index 1f32e17..f96c1ae 100644
--- a/lm_precomp.yml
+++ b/lm_precomp.yml
@@ -95,7 +95,7 @@ dependencies:
   - libprotobuf=3.13.0.1=hd408876_0
   - libsodium=1.0.18=h36c2ea0_1
   - libssh2=1.10.0=ha56f1ee_2
-  - libstdcxx-ng=11.2.0=he4da1e4_16
+  - libstdcxx-ng>=13.2.0
   - libtiff=4.3.0=h542a066_3
   - libuuid=2.32.1=h7f98852_1000
   - libuv=1.43.0=h7f98852_0
diff --git a/src/CMakeLists.txt b/src/CMakeLists.txt
index 9780e54..3c0fa05 100644
--- a/src/CMakeLists.txt
+++ b/src/CMakeLists.txt
@@ -93,6 +93,7 @@ if (OPT_CUDA)
         target_link_libraries(lmcore PUBLIC ${NVTX_LIBRARY})
     endif ()
     set_property(TARGET lmcore PROPERTY CUDA_SEPARABLE_COMPILATION ON)
+    set_property(TARGET lmcore PROPERTY CUDA_RESOLVE_DEVICE_SYMBOLS ON)
     set_property(TARGET lmcore PROPERTY CUDA_STANDARD 11)
 endif ()
 
diff --git a/src/cmd/CMakeLists.txt b/src/cmd/CMakeLists.txt
index 49f4eca..0e10b81 100644
--- a/src/cmd/CMakeLists.txt
+++ b/src/cmd/CMakeLists.txt
@@ -2,8 +2,9 @@ add_library(lmmain STATIC "${CMAKE_CURRENT_LIST_DIR}/common.cpp")
 target_include_directories(lmmain PRIVATE lmcore)
 target_link_libraries(lmmain PUBLIC lmcore)
 
-add_executable(lm "${CMAKE_CURRENT_LIST_DIR}/MainSA.cpp") 
-target_link_libraries(lm PRIVATE lmmain)
+add_executable(lm_cli "${CMAKE_CURRENT_LIST_DIR}/MainSA.cpp") 
+set_target_properties(lm_cli PROPERTIES OUTPUT_NAME lm)
+target_link_libraries(lm_cli PRIVATE lmmain)
 
 add_executable(lm_setdm "${CMAKE_CURRENT_LIST_DIR}/lm_setdm.cpp")
 target_link_libraries(lm_setdm PUBLIC lmcore)
@@ -14,7 +15,7 @@ target_link_libraries(lm_setp PUBLIC lmcore)
 add_executable(lm_setrm "${CMAKE_CURRENT_LIST_DIR}/lm_setrm.cpp")
 target_link_libraries(lm_setrm PUBLIC lmcore)
 
-install(TARGETS lm lm_setdm lm_setp lm_setrm RUNTIME DESTINATION bin)
+install(TARGETS lm_cli lm_setdm lm_setp lm_setrm RUNTIME DESTINATION bin)
 
 if (OPT_MPI)
      add_executable(mpilm "${CMAKE_CURRENT_LIST_DIR}/MainMPI.cpp")
@@ -24,7 +25,7 @@ endif ()
 
 if (OPT_PYTHON)
      add_executable(lm_python "${CMAKE_CURRENT_LIST_DIR}/lm_python.cpp" "${CMAKE_BINARY_DIR}/lm_module_pack.h")
-     target_include_directories(lm_python PRIVATE ${SWIG_MODULE_pythonlmstatic_REAL_NAME})
-     target_link_libraries(lm_python PRIVATE ${SWIG_MODULE_pythonlmstatic_REAL_NAME})
+     target_include_directories(lm_python PRIVATE ${SWIG_MODULE_lmstatic_REAL_NAME})
+     target_link_libraries(lm_python PRIVATE ${SWIG_MODULE_lmstatic_REAL_NAME})
      install(TARGETS lm_python RUNTIME DESTINATION bin)
 endif ()
diff --git a/src/cmd/lm_python.cpp b/src/cmd/lm_python.cpp
index 93339dc..4620315 100644
--- a/src/cmd/lm_python.cpp
+++ b/src/cmd/lm_python.cpp
@@ -111,7 +111,7 @@ void initPython();
 void finalizePython();
 void startInterpreter();
 void executeScript(string filename, list<string> arguments);
-extern "C" PyObject *PyInit__lm(void);
+extern "C" PyObject *PyInit__lmstatic(void);
 
 // Allocate the profile space.
 PROF_ALLOC;
@@ -287,7 +287,7 @@ void discoverEnvironment()
 
 void initPython()
 {
-	PyImport_AppendInittab("_lm", PyInit__lm);
+	PyImport_AppendInittab("_lmstatic", PyInit__lmstatic);
 	Py_Initialize();
 
 	PyObject *builtins = PyEval_GetBuiltins();
diff --git a/src/swig/CMakeLists.txt b/src/swig/CMakeLists.txt
index e1aeab4..a70a002 100644
--- a/src/swig/CMakeLists.txt
+++ b/src/swig/CMakeLists.txt
@@ -5,53 +5,68 @@ if (OPT_PYTHON)
     set_property(SOURCE "${CMAKE_CURRENT_LIST_DIR}/lm.i"
                  PROPERTY CPLUSPLUS ON)
 
-    swig_add_library(pythonlm
+    set_property(SOURCE "${CMAKE_CURRENT_LIST_DIR}/lm.i"
+                 APPEND PROPERTY COMPILE_OPTIONS "-module" "lm")
+
+    # Shared library target (imports as _lm)
+    swig_add_library(lm
          TYPE SHARED
          LANGUAGE python
          SOURCES "${CMAKE_CURRENT_LIST_DIR}/lm.i")
 
-    target_include_directories(${SWIG_MODULE_pythonlm_REAL_NAME}
+    target_include_directories(${SWIG_MODULE_lm_REAL_NAME}
          PRIVATE
             lmcore
             ${NUMPY_INCLUDE_DIR}
             ${PYTHON_INCLUDE_DIRS})
 
-    target_link_libraries(${SWIG_MODULE_pythonlm_REAL_NAME}
+    target_link_libraries(${SWIG_MODULE_lm_REAL_NAME}
          PRIVATE
             lmcore
             ${PYTHON_LIBRARIES})
 
-    swig_add_library(pythonlmstatic
+    # Separate output directory for the static wrapper to prevent race conditions on lm.py
+    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/static_out")
+    set(CMAKE_SWIG_OUTDIR "${CMAKE_CURRENT_BINARY_DIR}/static_out")
+    set(SWIG_OUTFILE_DIR "${CMAKE_CURRENT_BINARY_DIR}/static_out")
+
+    # Static library target (used by lm_python)
+    swig_add_library(lmstatic
          TYPE STATIC
          LANGUAGE python
          SOURCES "${CMAKE_CURRENT_LIST_DIR}/lm.i")
 
-    target_include_directories(${SWIG_MODULE_pythonlmstatic_REAL_NAME}
+    unset(CMAKE_SWIG_OUTDIR)
+    unset(SWIG_OUTFILE_DIR)
+
+    add_dependencies(${SWIG_MODULE_lmstatic_REAL_NAME} ${SWIG_MODULE_lm_REAL_NAME})
+
+    target_include_directories(${SWIG_MODULE_lmstatic_REAL_NAME}
         PUBLIC
             lmcore
             ${NUMPY_INCLUDE_DIR}
             ${PYTHON_INCLUDE_DIRS})
 
-    target_link_libraries(${SWIG_MODULE_pythonlmstatic_REAL_NAME}
+    target_link_libraries(${SWIG_MODULE_lmstatic_REAL_NAME}
         PUBLIC
             lmcore
             ${PYTHON_LIBRARIES})
 
+    # Embed the static wrapper's lm.py
     add_custom_command(
         OUTPUT "${CMAKE_BINARY_DIR}/lm_module_pack.h"
-        DEPENDS ${SWIG_MODULE_pythonlmstatic_REAL_NAME}
+        DEPENDS ${SWIG_MODULE_lmstatic_REAL_NAME}
         WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
         COMMAND
             ${PYTHON_EXECUTABLE}
                 ${CMAKE_CURRENT_LIST_DIR}/embed_lm_dot_py.py
-                ${CMAKE_BINARY_DIR}/lm.py
+                ${CMAKE_CURRENT_BINARY_DIR}/static_out/lm.py
                 ${CMAKE_BINARY_DIR}/lm_module_pack.h)
 
     add_custom_target(lm_module_pack
         DEPENDS "${CMAKE_BINARY_DIR}/lm_module_pack.h")
 
     set(SWIG_LM_PYTHON_WRAPPER "${CMAKE_BINARY_DIR}/lm.py")
-    set(SWIG_LM_MODULE_OLD_NAME "${CMAKE_BINARY_DIR}/${SWIG_MODULE_pythonlm_REAL_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX}")
 
     execute_process(
         COMMAND ${PYTHON_EXECUTABLE} "-c"
@@ -60,30 +75,13 @@ if (OPT_PYTHON)
         OUTPUT_STRIP_TRAILING_WHITESPACE
     )
 
-    if(APPLE)
-        add_custom_target(
-            "${SWIG_LM_MODULE_NAME}" ALL
-            DEPENDS "${SWIG_MODULE_pythonlm_REAL_NAME}"
-            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
-            COMMAND
-                ${CMAKE_COMMAND} -E rename "${SWIG_LM_MODULE_OLD_NAME}" "${SWIG_LM_MODULE_NAME}"
-            COMMAND # Not sure if this is necessary for Darwin
-                ${CMAKE_INSTALL_NAME_TOOL} -id "@rpath/${SWIG_LM_MODULE_NAME}" "${SWIG_LM_MODULE_NAME}"
-            )
-    else()
-        add_custom_target(
-            "${SWIG_LM_MODULE_NAME}" ALL
-            DEPENDS "${SWIG_MODULE_pythonlm_REAL_NAME}"
-            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
-            COMMAND
-                ${CMAKE_COMMAND} -E rename "${SWIG_LM_MODULE_OLD_NAME}" "${SWIG_LM_MODULE_NAME}"
-        )
-    endif()
-
     configure_file(${CMAKE_CURRENT_LIST_DIR}/setup.py.in setup.py)
 
     install(
-        CODE "execute_process(COMMAND ${PYTHON_EXECUTABLE} setup.py install)"
+        CODE "execute_process(COMMAND ${PYTHON_EXECUTABLE} setup.py install RESULT_VARIABLE install_res)
+              if(NOT install_res EQUAL 0)
+                  message(FATAL_ERROR \"setup.py install failed with exit code: \${install_res}\")
+              endif()"
         WORKING_DIRECTORY "${CMAKE_BINARY_DIR}")
 
 endif ()
diff --git a/src/swig/setup.py.in b/src/swig/setup.py.in
index 23f705c..18d0a31 100644
--- a/src/swig/setup.py.in
+++ b/src/swig/setup.py.in
@@ -8,7 +8,14 @@ class CompiledLibInstall(install):
     def run(self):
         install_dir = get_python_lib()
         shutil.copy("@SWIG_LM_PYTHON_WRAPPER@", install_dir)
-        shutil.copy("@SWIG_LM_MODULE_NAME@", install_dir)
+        copied = False
+        for name in ["_lm.so", "@SWIG_LM_MODULE_NAME@"]:
+            if os.path.exists(name):
+                shutil.copy(name, os.path.join(install_dir, "@SWIG_LM_MODULE_NAME@"))
+                copied = True
+                break
+        if not copied:
+            raise FileNotFoundError("Could not find _lm.so or @SWIG_LM_MODULE_NAME@ to install.")
 
 setup(
     name='@PROJECT_NAME@',
EOF
    git apply lm_build_fixes.patch || true
    rm lm_build_fixes.patch
    cd ..
else
    echo "Lattice_Microbes already exists, skipping clone."
fi

# 2. LAMMPS
if [ ! -d "lammps-stable" ]; then
    echo "Cloning LAMMPS (stable)..."
    git clone --depth 1 -b stable https://github.com/lammps/lammps.git lammps-stable
else
    echo "lammps-stable already exists, skipping clone."
fi

# 3. btree_chromo_gpu
if [ ! -d "btree_chromo_gpu" ]; then
    echo "Cloning btree_chromo_gpu..."
    git clone https://github.com/Luthey-Schulten-Lab/btree_chromo_gpu.git
else
    echo "btree_chromo_gpu already exists, skipping clone."
fi

# 4. FreeDTS
if [ ! -d "FreeDTS" ]; then
    echo "Cloning FreeDTS..."
    git clone https://github.com/weria-pezeshkian/FreeDTS.git
else
    echo "FreeDTS already exists, skipping clone."
fi

# 5. sc_chain_generation
if [ ! -d "sc_chain_generation" ]; then
    echo "Cloning sc_chain_generation..."
    git clone https://github.com/Luthey-Schulten-Lab/sc_chain_generation.git
else
    echo "sc_chain_generation already exists, skipping clone."
fi

# 6. odecell
if [ ! -d "odecell" ]; then
    echo "Cloning odecell..."
    git clone https://github.com/Luthey-Schulten-Lab/odecell.git
else
    echo "odecell already exists, skipping clone."
fi

# Create symlink for btree_chromo (expected name for pipeline)
if [ ! -L "btree_chromo" ] && [ ! -d "btree_chromo" ]; then
    ln -sf btree_chromo_gpu btree_chromo
fi

echo "======================================================================"
echo ">>> Preparing and Creating Conda Environment in ./py ..."
echo "======================================================================"

# Strip build hashes from lm_precomp.yml for cross-platform portability
python3 << 'EOF'
with open('Lattice_Microbes/lm_precomp.yml', 'r') as f:
    lines = f.readlines()
new_lines = []
in_pip = False
for line in lines:
    stripped = line.strip()
    if not stripped:
        new_lines.append(line)
        continue
    if stripped.startswith('- pip:'):
        in_pip = True
        new_lines.append(line)
        continue
    if in_pip:
        if line.startswith('      - ') or line.startswith('    - '):
            new_lines.append(line)
            continue
        else:
            in_pip = False
    parts = stripped.split('=')
    if len(parts) == 3 and stripped.startswith('- '):
        pkg = parts[0].replace('- ', '').strip()
        ver = parts[1].strip()
        new_lines.append(f'  - {pkg}={ver}\n')
    else:
        new_lines.append(line)
with open('Lattice_Microbes/lm_precomp_portable.yml', 'w') as f:
    f.writelines(new_lines)
EOF


# Create/Update the conda environment at ../py (Minimal_Cell_4DWCM/py)
if [ -d "../py" ]; then
    echo "Conda environment already exists at ./py, updating package list..."
    conda env update -p ../py -f Lattice_Microbes/lm_precomp_portable.yml
else
    echo "Creating new Conda environment at ./py..."
    conda env create -p ../py -f Lattice_Microbes/lm_precomp_portable.yml -y
fi

# Sourcing conda to allow environment activation inside this script
CONDA_BASE=$(conda info --base)
source "$CONDA_BASE/etc/profile.d/conda.sh"
conda activate ../py
conda install -y -c conda-forge "cmake>=3.20"

# Clean conda compiler/sysroot variables to prevent header conflicts between system compilers and conda sysroot
unset CONDA_BUILD_SYSROOT
unset CC
unset CXX
unset CFLAGS
unset CXXFLAGS
unset CPPFLAGS
unset LDFLAGS
export CMAKE_PREFIX_PATH="$CONDA_PREFIX"



echo "======================================================================"
echo ">>> Adapting GPU Capabilities & Compiler Configurations..."
echo "======================================================================"

# 1. Detect GPU Compute Capability (sm value)
if command -v nvidia-smi &> /dev/null; then
    CUDA_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n 1 | tr -d '.')
    if [ -z "$CUDA_CAP" ]; then
        CUDA_CAP="61"
    fi
else
    CUDA_CAP="61"
fi
echo "Detected GPU Compute Capability (SM): $CUDA_CAP"

# Map CUDA Capability to Kokkos GPU architecture flag
case "$CUDA_CAP" in
    60) KOKKOS_ARCH="PASCAL60" ;;
    61) KOKKOS_ARCH="PASCAL61" ;;
    70) KOKKOS_ARCH="VOLTA70" ;;
    75) KOKKOS_ARCH="TURING75" ;;
    80) KOKKOS_ARCH="AMPERE80" ;;
    86) KOKKOS_ARCH="AMPERE86" ;;
    89) KOKKOS_ARCH="ADA89" ;;
    90) KOKKOS_ARCH="HOPPER90" ;;
    *) KOKKOS_ARCH="PASCAL61" ;;
esac
echo "Mapped Kokkos GPU Architecture: $KOKKOS_ARCH"

# Detect Host CPU architecture for Kokkos
if grep -qi "amd" /proc/cpuinfo; then
    KOKKOS_HOST_ARCH="ZEN3"
else
    KOKKOS_HOST_ARCH="SKL"
fi
echo "Mapped Kokkos Host CPU Architecture: $KOKKOS_HOST_ARCH"

# 2. Detect compatible C/C++ compiler for nvcc (must be <= GCC 13)
DEFAULT_VER=$(g++ -dumpversion 2>/dev/null | cut -d. -f1)
if [ -n "$DEFAULT_VER" ] && [ "$DEFAULT_VER" -le 13 ]; then
    COMPILER_CXX="g++"
    COMPILER_CC="gcc"
else
    COMPILER_CXX=""
    COMPILER_CC=""
    for ver in 13 12 11; do
        if command -v "g++-$ver" &>/dev/null; then
            COMPILER_CXX="g++-$ver"
            COMPILER_CC="gcc-$ver"
            break
        fi
    done
    if [ -z "$COMPILER_CXX" ]; then
        COMPILER_CXX="g++"
        COMPILER_CC="gcc"
    fi
fi
echo "Selected compilers for CUDA builds: CXX=$COMPILER_CXX, CC=$COMPILER_CC"

# 3. Detect OpenMPI paths dynamically
MPI_INC_DIR=$(mpicxx -show | grep -o '\-I[^ ]*' | head -n 1 | sed 's/-I//' || true)
MPI_LIB_DIR=$(mpicxx -show | grep -o '\-L[^ ]*' | head -n 1 | sed 's/-L//' || true)
if [ -z "$MPI_INC_DIR" ]; then MPI_INC_DIR="/usr/lib/x86_64-linux-gnu/openmpi/include"; fi
if [ -z "$MPI_LIB_DIR" ]; then MPI_LIB_DIR="/usr/lib/x86_64-linux-gnu/openmpi/lib"; fi
echo "Detected OpenMPI Include Path: $MPI_INC_DIR"
echo "Detected OpenMPI Library Path: $MPI_LIB_DIR"

echo "======================================================================"
echo ">>> Building LAMMPS with Kokkos/CUDA..."
echo "======================================================================"

# Apply the FLERR signature patch to the custom angle styles in LAMMPS:
cp btree_chromo_gpu/LAMMPS_src_additions/angle_polytorsion.cpp lammps-stable/src/
cp btree_chromo_gpu/LAMMPS_src_additions/angle_polytorsion.h lammps-stable/src/
cp btree_chromo_gpu/LAMMPS_src_additions/angle_polytorsionend.cpp lammps-stable/src/
cp btree_chromo_gpu/LAMMPS_src_additions/angle_polytorsionend.h lammps-stable/src/

cp btree_chromo_gpu/LAMMPS_src_additions/angle_polytorsion_omp.cpp lammps-stable/src/OPENMP/
cp btree_chromo_gpu/LAMMPS_src_additions/angle_polytorsion_omp.h lammps-stable/src/OPENMP/
cp btree_chromo_gpu/LAMMPS_src_additions/fix_brownian_base_omp.cpp lammps-stable/src/OPENMP/
cp btree_chromo_gpu/LAMMPS_src_additions/fix_brownian_base_omp.h lammps-stable/src/OPENMP/
cp btree_chromo_gpu/LAMMPS_src_additions/fix_brownian_asphere_omp.cpp lammps-stable/src/OPENMP/
cp btree_chromo_gpu/LAMMPS_src_additions/fix_brownian_asphere_omp.h lammps-stable/src/OPENMP/

cp btree_chromo_gpu/LAMMPS_src_additions/OPENMP.cmake lammps-stable/cmake/Modules/Packages/

cp btree_chromo_gpu/LAMMPS_src_additions/fix_brownian_kokkos.cpp lammps-stable/src/KOKKOS/
cp btree_chromo_gpu/LAMMPS_src_additions/fix_brownian_kokkos.h lammps-stable/src/KOKKOS/
cp btree_chromo_gpu/LAMMPS_src_additions/fix_addforce_kokkos.cpp lammps-stable/src/KOKKOS/
cp btree_chromo_gpu/LAMMPS_src_additions/fix_addforce_kokkos.h lammps-stable/src/KOKKOS/


python3 -c "
for filename in ['lammps-stable/src/angle_polytorsion.cpp', 'lammps-stable/src/angle_polytorsionend.cpp']:
    with open(filename, 'r') as f:
        content = f.read()
    content = content.replace('domain->minimum_image(delx,dely,delz);', 'domain->minimum_image(FLERR,delx,dely,delz);')
    with open(filename, 'w') as f:
        f.write(content)
"

# Configure and compile LAMMPS
cmake -B lammps-stable/build_GPU_Kokkos/ -S lammps-stable/cmake/ \
  -DCMAKE_CXX_COMPILER=$COMPILER_CXX \
  -DCMAKE_C_COMPILER=$COMPILER_CC \
  -DBUILD_MPI=yes \
  -DBUILD_OMP=yes \
  -DLAMMPS_MACHINE=GPU_Kokkos \
  -DBUILD_SHARED_LIBS=yes \
  -DCMAKE_INSTALL_PREFIX=$SOFT_DIR/LAMMPS/GPU_Kokkos \
  -DPKG_GPU=yes \
  -DPKG_KOKKOS=on \
  -DMPIEXEC_EXECUTABLE=$(which mpirun || echo "/usr/bin/mpirun") \
  -DKokkos_ARCH_${KOKKOS_HOST_ARCH}=yes \
  -DKokkos_ENABLE_OMP=yes \
  -DKokkos_ARCH_${KOKKOS_ARCH}=yes \
  -DKokkos_ENABLE_CUDA=yes \
  -DGPU_API=cuda \
  -DGPU_ARCH=sm_${CUDA_CAP} \
  -DCMAKE_CUDA_ARCHITECTURES=${CUDA_CAP} \
  -DPKG_OPENMP=yes \
  -DPKG_MOLECULE=yes \
  -DPKG_ASPHERE=yes \
  -DPKG_BROWNIAN=yes \
  -DPKG_RIGID=yes \
  -DPKG_CG-DNA=yes \
  -DPKG_EXTRA-MOLECULE=yes

cmake --build lammps-stable/build_GPU_Kokkos/ -j$(nproc)

echo "======================================================================"
echo ">>> Building btree_chromo_gpu..."
echo "======================================================================"

# Apply compiler warning and MPI finalize fixes:
python3 -c "
with open('btree_chromo_gpu/src/btree.cpp', 'r') as f:
    c = f.read()
c = c.replace('size_t branch_idx;', 'size_t branch_idx = 0;')
with open('btree_chromo_gpu/src/btree.cpp', 'w') as f:
    f.write(c)
"

python3 -c "
with open('btree_chromo_gpu/src/LAMMPS_simulator.cpp', 'r') as f:
    content = f.read()
old = '''  MPI_Finalized(&sim_MPI_finalized);
  if (!sim_MPI_finalized) MPI_Finalize();'''
new = '''  int mpi_initialized = 0;
  MPI_Initialized(&mpi_initialized);
  MPI_Finalized(&sim_MPI_finalized);
  if (mpi_initialized && !sim_MPI_finalized) MPI_Finalize();'''
content = content.replace(old, new)
with open('btree_chromo_gpu/src/LAMMPS_simulator.cpp', 'w') as f:
    f.write(content)
"

# Create customized local Makefile for btree_chromo (with dynamically resolved MPI paths)
cat << EOF > btree_chromo_gpu/Makefile
CXX      := $COMPILER_CXX
CXXFLAGS := -pedantic-errors -Wall -Wextra -Werror

OpenMPI_LIB := $MPI_LIB_DIR
fmt_LIB := /usr/lib/x86_64-linux-gnu
LAMMPS_LIB := $SOFT_DIR/lammps-stable/build_GPU_Kokkos

OpenMPI_INC := $MPI_INC_DIR
fmt_INC := /usr/include
boost_INC := /usr/include
LAMMPS_INC := $SOFT_DIR/lammps-stable/src

BASE_LDFLAGS  := -lstdc++ -lm -std=c++17
OPENMPI_LDFLAGS := -L\${OpenMPI_LIB} -lmpi -pthread -Wl,-rpath -Wl,\${OpenMPI_LIB} -Wl,--enable-new-dtags
FMT_LDFLAGS := -L\${fmt_LIB} -lfmt
LAMMPS_LDFLAGS := -L\${LAMMPS_LIB} -llammps_GPU_Kokkos -Wl,-rpath -Wl,\${LAMMPS_LIB}
LDFLAGS := \${BASE_LDFLAGS} \${OPENMPI_LDFLAGS} \${FMT_LDFLAGS} \${LAMMPS_LDFLAGS}

BASE_INCLUDE  := -Iinclude/ -I\$(CONDA_PREFIX)/include
OPENMPI_INCLUDE := -I\${OpenMPI_INC}
FMT_INCLUDE := -I\${fmt_INC}
BOOST_INCLUDE := -I\${boost_INC}
LAMMPS_INCLUDE := -I\${LAMMPS_INC}
INCLUDE := \${BASE_INCLUDE} \${OPENMPI_INCLUDE} \${FMT_INCLUDE} \${BOOST_INCLUDE} \${LAMMPS_INCLUDE}

BUILD    := ./build
OBJ_DIR  := \$(BUILD)/objects
APP_DIR  := \$(BUILD)/apps

TARGET   := btree_chromo

SRC      := \$(wildcard src/*.cpp)

OBJECTS  := \$(SRC:%.cpp=\$(OBJ_DIR)/%.o)
DEPENDENCIES := \$(OBJECTS:.o=.d)

all: build \$(APP_DIR)/\$(TARGET)

\$(OBJ_DIR)/%.o: %.cpp
	@mkdir -p \$(@D)
	\$(CXX) \$(CXXFLAGS) \$(INCLUDE) -c $< -MMD -o \$@

\$(APP_DIR)/\$(TARGET): \$(OBJECTS)
	@mkdir -p \$(@D)
	\$(CXX) \$(CXXFLAGS) -o \$(APP_DIR)/\$(TARGET) \$^ \$(LDFLAGS)

-include \$(DEPENDENCIES)

.PHONY: all build clean debug release info

build:
	@mkdir -p \$(APP_DIR)
	@mkdir -p \$(OBJ_DIR)

debug: CXXFLAGS += -DDEBUG -g -ggdb3
debug: all

release: CXXFLAGS += -O2
release: all

clean:
	-@rm -rvf \$(OBJ_DIR)/*
	-@rm -rvf \$(APP_DIR)/*

info:
	@echo "[*] Application dir: \${APP_DIR}     "
	@echo "[*] Object dir:      \${OBJ_DIR}     "
	@echo "[*] Sources:         \${SRC}         "
	@echo "[*] Objects:         \${OBJECTS}     "
	@echo "[*] Dependencies:    \${DEPENDENCIES}"
	@echo "[*] Include:         \${INCLUDE}     "
EOF

# Compile btree_chromo_gpu
cd btree_chromo_gpu
make clean
make -j$(nproc)
cd ..

echo "======================================================================"
echo ">>> Building Lattice_Microbes..."
echo "======================================================================"
mkdir -p Lattice_Microbes/build
cd Lattice_Microbes/build
cmake ../src/ \
  -DCMAKE_C_COMPILER=$COMPILER_CC \
  -DCMAKE_CXX_COMPILER=$COMPILER_CXX \
  -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
  -DMPD_GLOBAL_T_MATRIX=True \
  -DMPD_GLOBAL_R_MATRIX=True \
  -DCUDA_ARCHITECTURES="$CUDA_CAP" \
  -DSWIG_EXECUTABLE=$CONDA_PREFIX/bin/swig
make -j$(nproc)
make install
cd ../..

echo "======================================================================"
echo ">>> Building FreeDTS..."
echo "======================================================================"
cd FreeDTS/version_2.1
./compile.sh
cd ../..

echo "======================================================================"
echo ">>> Building sc_chain_generation..."
echo "======================================================================"
cd sc_chain_generation/src
make FC=gfortran gen_sc_chain
cd ..
mkdir -p fortran
ln -sf ../src/gen_sc_chain fortran/gen_sc_chain
cd ..

echo "======================================================================"
echo ">>> Installing odecell and dependencies..."
echo "======================================================================"
# Install precompiled libraries from conda-forge to prevent wheel compilation failures:
conda install -y -c conda-forge python-libsbml pycvodes cobra swiglpk plotnine cmake>=3.20

# Install odecell in development/editable mode:
cd odecell
pip install -e .
cd ..

echo "======================================================================"
echo ">>> SETUP COMPLETED SUCCESSFULLY!"
echo "======================================================================"
cd ..

# Apply the rescueDNA fix to SpatialDnaDynamics.py
python3 -c "
with open('SpatialDnaDynamics.py', 'r') as f:
    content = f.read()

target = '''    oldDNAFile = workDir + \'dna_monomers_{:d}.bin\'.format(sim_properties[\'last_last_DNA_step\'])
    
    rescueDNAFile = workDir + \'dna_monomers_{:d}.bin\'.format(sim_properties[\'last_DNA_step\'])
    
    os.system(\'cp \' + oldDNAFile + \' \' + rescueDNAFile)
    
#     oldQuatFile = workDir + \'dna_quats_{:d}.bin\'.format(sim_properties[\'last_last_DNA_step\'])
    
#     rescueQuatFile = workDir + \'dna_quats_{:d}.bin\'.format(sim_properties[\'last_DNA_step\'])
    
#     os.system(\'cp \' + oldQuatFile + \' \' + rescueQuatFile)
    
    oldRepState = workDir + \'rep_state_{:d}.txt\'.format(sim_properties[\'last_last_DNA_step\'])
                                                          
    rescueRepState = workDir + \'rep_state_{:d}.txt\'.format(sim_properties[\'last_DNA_step\'])
                                                          
    os.system(\'cp \' + oldRepState + \' \' + rescueRepState)
    
    oldChromoTopo = workDir + \'chromo_topo_{:d}.dat\'.format(sim_properties[\'last_last_DNA_step\'])
    
    rescueChromoTopo = workDir + \'chromo_topo_{:d}.dat\'.format(sim_properties[\'last_DNA_step\'])
    
    os.system(\'cp \' + oldChromoTopo + \' \' + rescueChromoTopo)'''

replacement = '''    last_last = sim_properties[\'last_last_DNA_step\']
    
    if last_last is None:
        oldDNAFile = workDir + \'x_chain_Syn3A_chromosome_init_rep00001.bin\'
        oldRepState = None
        oldChromoTopo = None
    else:
        oldDNAFile = workDir + \'dna_monomers_{:d}.bin\'.format(last_last)
        oldRepState = workDir + \'rep_state_{:d}.txt\'.format(last_last)
        oldChromoTopo = workDir + \'chromo_topo_{:d}.dat\'.format(last_last)
        
    rescueDNAFile = workDir + \'dna_monomers_{:d}.bin\'.format(sim_properties[\'last_DNA_step\'])
    rescueRepState = workDir + \'rep_state_{:d}.txt\'.format(sim_properties[\'last_DNA_step\'])
    rescueChromoTopo = workDir + \'chromo_topo_{:d}.dat\'.format(sim_properties[\'last_DNA_step\'])
    
    if oldDNAFile and os.path.exists(oldDNAFile):
        os.system(\'cp \' + oldDNAFile + \' \' + rescueDNAFile)
        
    if oldRepState and os.path.exists(oldRepState):
        os.system(\'cp \' + oldRepState + \' \' + rescueRepState)
        
    if oldChromoTopo and os.path.exists(oldChromoTopo):
        os.system(\'cp \' + oldChromoTopo + \' \' + rescueChromoTopo)'''

if target in content:
    content = content.replace(target, replacement)
    with open('SpatialDnaDynamics.py', 'w') as f:
        f.write(content)
    print('Applied rescueDNA fix to SpatialDnaDynamics.py successfully!')
else:
    print('rescueDNA fix already applied or target not found.')
"


echo ""
echo "To run a simulation using your local tools, activate the local environment and run:"
echo ""
echo "  conda activate ./py"
echo "  python Whole_Cell_Minimal_Cell.py -od replicate1 -t 1200 -cd 0 -drs 13 -dsd ./software/"
echo ""
