# 默认使用 clang 作为 C 编译器；`?=` 表示如果外部已经传了 CC，就不覆盖外部设置。
CC ?= clang

# CPU C 编译选项：
# -Ofast 开启较激进优化；
# 后面几个 -Wno-* 用来关闭本项目里已知但不影响构建的编译警告。
CFLAGS = -Ofast -Wno-unused-result -Wno-ignored-pragmas -Wno-unknown-attributes

# 链接器参数，默认先留空；平台检测时可能继续追加。
LDFLAGS =

# 链接库参数；CPU 版本默认只需要数学库 libm。
LDLIBS = -lm

# C/C++ 头文件搜索路径，默认先留空；OpenMP、Windows 等分支会按需追加。
INCLUDES =

# 条件编译参数：后面会先测试编译器是否支持，支持才加入 CFLAGS。
CFLAGS_COND = -march=native

# Find nvcc
# 中文：寻找 NVIDIA CUDA 编译器 nvcc，后续据此决定是否构建 CUDA 目标。
# 记录当前系统名称，例如 Darwin/Linux；后面用它区分 macOS、Linux、Windows。
SHELL_UNAME = $(shell uname)

# 非 Windows 默认用 rm -f 删除生成文件。
REMOVE_FILES = rm -f

# CPU 编译输出参数；$@ 是 Makefile 自动变量，表示当前 target 名。
OUTPUT_FILE = -o $@

# CUDA 编译输出参数；默认也使用 -o target。
CUDA_OUTPUT_FILE = -o $@

# Default O3 CPU optimization level for NVCC (0 for fastest compile time)
# 中文：NVCC 调用宿主 CPU 编译器时默认使用 O3；如果想加快编译可执行 `make FORCE_NVCC_O=0 ...`。
FORCE_NVCC_O ?= 3

# NVCC flags
# 中文：下面定义 CUDA 编译器 nvcc 的基础编译参数。
# -t=0 is short for --threads, 0 = number of CPUs on the machine
# 中文：`--threads=0`/`-t=0` 表示让 nvcc 使用机器上的全部 CPU 线程来并行编译。
# --use_fast_math 使用更快但可能略牺牲精度的数学实现；
# -std=c++17 指定 CUDA/C++ 代码按 C++17 编译；
# -O$(FORCE_NVCC_O) 使用上面定义的优化等级。
NVCC_FLAGS = --threads=0 -t=0 --use_fast_math -std=c++17 -O$(FORCE_NVCC_O)

# CUDA 链接参数：主线 CUDA 版本默认依赖 cuBLAS 和 cuBLASLt。
NVCC_LDFLAGS = -lcublas -lcublasLt

# CUDA 头文件搜索路径，后面会按 cuDNN/OpenMPI 等检测结果追加。
NVCC_INCLUDES =

# CUDA 额外链接库，后面会按 NCCL/OpenMPI 等检测结果追加。
NVCC_LDLIBS =

# 这里变量名看起来像 NCCL includes 的占位，目前没有在本 Makefile 后续使用。
NCLL_INCUDES =

# cuDNN attention 的额外 object 文件；只有启用 cuDNN 时才会设置为具体路径。
NVCC_CUDNN =

# By default we don't build with cudnn because it blows up compile time from a few seconds to ~minute
# 中文：默认不启用 cuDNN，因为会把编译时间从几秒拉长到约一分钟；需要时执行 `make USE_CUDNN=1 ...`。
USE_CUDNN ?= 0

# We will place .o files in the `build` directory (create it if it doesn't exist)
# 中文：中间 `.o`/`.obj` 文件统一放进 `build` 目录；如果目录不存在就创建。
BUILD_DIR = build

# Windows 下用 cmd 风格命令创建 build 目录并删除 .obj 文件。
ifeq ($(OS), Windows_NT)
  # Windows 的 `mkdir` 写法；`$(shell ...)` 在解析 Makefile 时执行。
  $(shell if not exist $(BUILD_DIR) mkdir $(BUILD_DIR))
  # Windows 清理 object 文件时删除 build 目录下的 .obj。
  REMOVE_BUILD_OBJECT_FILES := del $(BUILD_DIR)\*.obj
else
  # Unix/macOS/Linux 下创建 build 目录；`-p` 表示已存在也不报错。
  $(shell mkdir -p $(BUILD_DIR))
  # Unix/macOS/Linux 下清理 build 目录中的 .o 文件。
  REMOVE_BUILD_OBJECT_FILES := rm -f $(BUILD_DIR)/*.o
endif

# Function to check if a file exists in the PATH
# 中文：定义一个小函数，用来判断某个可执行文件是否能在 PATH 里找到。
ifneq ($(OS), Windows_NT)
# 非 Windows 用 `which <cmd>` 检查命令是否存在。
define file_exists_in_path
  $(which $(1) 2>/dev/null)
endef
else
# Windows 用 `where <cmd>` 检查命令是否存在。
define file_exists_in_path
  $(shell where $(1) 2>nul)
endef
endif

# 如果不是 CI 环境，就尝试查询本机 GPU 信息；CI 上通常不依赖真实 GPU。
ifneq ($(CI),true) # if not in CI, then use the GPU query
  # 如果用户没有显式传 GPU_COMPUTE_CAPABILITY，就尝试自动检测。
  ifndef GPU_COMPUTE_CAPABILITY # set to defaults if: make GPU_COMPUTE_CAPABILITY=
    # 只有找到 nvidia-smi 才能查询 GPU compute capability。
    ifneq ($(call file_exists_in_path, nvidia-smi),)
      # Get the compute capabilities of all GPUs
      # 中文：查询所有 GPU 的 compute capability，例如 8.0、8.6、9.0。
      # Remove decimal points, sort numerically in ascending order, and select the first (lowest) value
      # 中文：去掉小数点后排序，取最低能力值，保证生成的二进制能在所有检测到的 GPU 上运行。
      GPU_COMPUTE_CAPABILITY=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | sed 's/\.//g' | sort -n | head -n 1)
      # 去掉命令输出两侧空白，避免拼接 nvcc flags 时出现脏字符。
      GPU_COMPUTE_CAPABILITY := $(strip $(GPU_COMPUTE_CAPABILITY))
    endif
  endif
endif

# set to defaults if - make GPU_COMPUTE_CAPABILITY= otherwise use the compute capability detected above
# 中文：如果检测到或用户指定了 GPU_COMPUTE_CAPABILITY，就把对应架构加入 nvcc 代码生成参数。
ifneq ($(GPU_COMPUTE_CAPABILITY),)
  # 同时生成 compute_xx 和 sm_xx 代码；compute 是 PTX，sm 是具体 GPU 架构机器码。
  NVCC_FLAGS += --generate-code arch=compute_$(GPU_COMPUTE_CAPABILITY),code=[compute_$(GPU_COMPUTE_CAPABILITY),sm_$(GPU_COMPUTE_CAPABILITY)]
endif

# autodect a lot of various supports on current platform
# 中文：下面开始自动检测当前平台支持的功能，例如 nvcc、OpenMP、cuDNN、NCCL、MPI。
$(info ---------------------------------------------)

# 非 Windows 平台走 Unix/macOS/Linux 检测路径。
ifneq ($(OS), Windows_NT)
  # 尝试查找 nvcc；找不到时变量为空，后面会跳过 CUDA target。
  NVCC := $(shell which nvcc 2>/dev/null)
  # CUDA 链接时额外链接 NVIDIA Management Library，用于读取 GPU 利用率等信息。
  NVCC_LDFLAGS += -lnvidia-ml

  # Function to test if the compiler accepts a given flag.
  # 中文：定义函数：用一个最小 C 程序测试当前 C 编译器是否接受某个 flag。
  define check_and_add_flag
    # 尝试用 $(CC) 加上传入 flag 编译空 main；成功则输出 yes。
    $(eval FLAG_SUPPORTED := $(shell printf "int main() { return 0; }\n" | $(CC) $(1) -x c - -o /dev/null 2>/dev/null && echo 'yes'))
    # 如果该 flag 被支持，就追加到 CFLAGS。
    ifeq ($(FLAG_SUPPORTED),yes)
        CFLAGS += $(1)
    endif
  endef

  # Check each flag and add it if supported
  # 中文：遍历 CFLAGS_COND 中的每个候选 flag，支持才加入，避免不同编译器报错。
  $(foreach flag,$(CFLAGS_COND),$(eval $(call check_and_add_flag,$(flag))))
else
  # Windows 分支：重置 CFLAGS，因为 MSVC 参数格式与 clang/gcc 不同。
  CFLAGS :=
  # Windows 清理命令；先删除 exe/obj/lib/exp/pdb 等产物，再接 del。
  REMOVE_FILES = del *.exe,*.obj,*.lib,*.exp,*.pdb && del
  # 在 Windows 分支里把系统名显式设为 Windows。
  SHELL_UNAME := Windows
  # Windows 下用 where nvcc 检测 CUDA 编译器。
  ifneq ($(shell where nvcc 2> nul),"")
    # 找到 nvcc，就启用 CUDA target。
    NVCC := nvcc
  else
    # 找不到 nvcc，就让 NVCC 为空，后续跳过 CUDA target。
    NVCC :=
  endif
  # Windows 下 C/C++ 编译器使用 MSVC cl。
  CC := cl
  # MSVC 编译参数：
  # /Idev 增加 include 路径；/Zi 生成调试信息；/O2 等开启优化；
  # /openmp:llvm 启用 OpenMP；多行末尾反斜杠表示下一行继续。
  CFLAGS = /Idev /Zi /nologo /W4 /WX- /diagnostics:column /sdl /O2 /Oi /Ot /GL /D _DEBUG /D _CONSOLE /D _UNICODE /D UNICODE /Gm- /EHsc /MD /GS /Gy /fp:fast /Zc:wchar_t /Zc:forScope /Zc:inline /permissive- \
   /external:W3 /Gd /TP /wd4996 /Fd$@.pdb /FC /openmp:llvm
  # Windows 分支里链接参数重新置空。
  LDFLAGS :=
  # Windows 分支里链接库参数重新置空。
  LDLIBS :=
  # Windows 分支里 include 参数重新置空。
  INCLUDES :=
  # Windows 下 CUDA 编译额外包含 dev 目录。
  NVCC_FLAGS += -I"dev"
  # Windows CI 构建和本地构建的输出处理略有不同。
  ifeq ($(WIN_CI_BUILD),1)
    # 打印当前是 Windows CI 构建。
    $(info Windows CI build)
    # CI 下 MSVC 链接输出直接写到 target。
    OUTPUT_FILE = /link /OUT:$@
    # CI 下 CUDA 输出直接写到 target。
    CUDA_OUTPUT_FILE = -o $@
  else
    # 打印当前是 Windows 本地构建。
    $(info Windows local build)
    # 本地 Windows 构建会把生成的 .exe 复制成无扩展名 target，方便脚本统一调用。
    OUTPUT_FILE = /link /OUT:$@ && copy /Y $@ $@.exe
    # CUDA 本地 Windows 构建同样复制一份无扩展名 target。
    CUDA_OUTPUT_FILE = -o $@ && copy /Y $@.exe $@
  endif
endif

# Check and include cudnn if available
# 中文：如果用户启用 cuDNN，就检测 cuDNN frontend 头文件并追加编译/链接参数。
# You can override the path to cudnn frontend by setting CUDNN_FRONTEND_PATH on the make command line
# 中文：可以通过 `make CUDNN_FRONTEND_PATH=/path/to/include USE_CUDNN=1 ...` 覆盖 cuDNN frontend 路径。
# By default, we look for it in HOME/cudnn-frontend/include and ./cudnn-frontend/include
# 中文：默认先找 `~/cudnn-frontend/include`，再找当前项目下的 `./cudnn-frontend/include`。
# Refer to the README for cuDNN install instructions
# 中文：cuDNN 和 cuDNN frontend 安装方式见 README。
ifeq ($(USE_CUDNN), 1)
  # Linux 下支持 cuDNN flash-attention 构建。
  ifeq ($(SHELL_UNAME), Linux)
    # 优先检查用户 home 目录下是否有 cudnn-frontend/include。
    ifeq ($(shell [ -d $(HOME)/cudnn-frontend/include ] && echo "exists"), exists)
      # 找到 cuDNN frontend，打印提示。
      $(info ✓ cuDNN found, will run with flash-attention)
      # 如果用户未指定路径，就用 home 目录下的 cudnn frontend。
      CUDNN_FRONTEND_PATH ?= $(HOME)/cudnn-frontend/include
    else ifeq ($(shell [ -d cudnn-frontend/include ] && echo "exists"), exists)
      # 如果项目目录下找到 cudnn-frontend，也可以启用。
      $(info ✓ cuDNN found, will run with flash-attention)
      # 如果用户未指定路径，就用项目目录下的 cudnn frontend。
      CUDNN_FRONTEND_PATH ?= cudnn-frontend/include
    else
      # 启用了 USE_CUDNN=1 但找不到 frontend，就直接报错终止。
      $(error ✗ cuDNN not found. See the README for install instructions and the Makefile for hard-coded paths)
    endif
    # 把 cuDNN frontend 头文件目录加入 CUDA include 路径。
    NVCC_INCLUDES += -I$(CUDNN_FRONTEND_PATH)
    # 链接 cuDNN runtime/library。
    NVCC_LDFLAGS += -lcudnn
    # 定义 ENABLE_CUDNN 宏，让 C/CUDA 源码走 cuDNN attention 分支。
    NVCC_FLAGS += -DENABLE_CUDNN
    # 启用 cuDNN 时需要额外编译 cudnn_att.cpp 到 object 文件。
    NVCC_CUDNN = $(BUILD_DIR)/cudnn_att.o
  else
    # 非 Linux 时继续区分 macOS 和 Windows。
    ifneq ($(OS), Windows_NT)
      # macOS 目前不支持 CUDA/cuDNN 构建，所以只打印提示。
      $(info → cuDNN is not supported on MAC OS right now)
    else
      # Windows cuDNN 分支。
      $(info ✓ Windows cuDNN found, will run with flash-attention)
      # 优先检查用户 home 目录下的 cudnn-frontend include。
      ifeq ($(shell if exist "$(HOMEDRIVE)$(HOMEPATH)\cudnn-frontend\include" (echo exists)),exists)
        CUDNN_FRONTEND_PATH ?= $(HOMEDRIVE)$(HOMEPATH)\cudnn-frontend\include #override on command line if different location
      else ifeq ($(shell if exist "cudnn-frontend\include" (echo exists)),exists)
        CUDNN_FRONTEND_PATH ?= cudnn-frontend\include #override on command line if different location
      else
        # Windows 下启用 cuDNN 但找不到 frontend，也直接报错终止。
        $(error ✗ cuDNN not found. See the README for install instructions and the Makefile for hard-coded paths)
      endif
      # Windows 下 cuDNN 安装目录的 include 路径默认值。
      CUDNN_INCLUDE_PATH ?= -I"C:\Program Files\NVIDIA\CUDNN\v9.1\include\12.4"
      # 同时把 cuDNN frontend 和 cuDNN 自身 include 路径拼进来。
      CUDNN_FRONTEND_PATH += $(CUDNN_INCLUDE_PATH)
      # Windows cuDNN frontend 需要 C++20，并设置一些 MSVC/NVCC 兼容参数。
      NVCC_FLAGS += --std c++20 -Xcompiler "/std:c++20" -Xcompiler "/EHsc /W0 /nologo /Ox /FS" -maxrregcount=0 --machine 64
      # Windows 下 object 文件扩展名为 .obj。
      NVCC_CUDNN = $(BUILD_DIR)\cudnn_att.obj
      # 追加 cuDNN frontend include。
      NVCC_INCLUDES += -I$(CUDNN_FRONTEND_PATH)
      # 追加 Windows cuDNN lib 路径和 cudnn 链接库。
      NVCC_LDFLAGS += -L"C:\Program Files\NVIDIA\CUDNN\v9.1\lib\12.4\x64" -lcudnn
      # 定义 ENABLE_CUDNN 宏，让源码启用 cuDNN 分支。
      NVCC_FLAGS += -DENABLE_CUDNN
    endif
  endif
else
  # 未启用 USE_CUDNN=1 时，明确提示 cuDNN 默认关闭。
  $(info → cuDNN is manually disabled by default, run make with `USE_CUDNN=1` to try to enable)
endif

# Check if OpenMP is available
# 中文：检测当前平台是否可用 OpenMP，多线程会显著加速 CPU 版本。
# This is done by attempting to compile an empty file with OpenMP flags
# 中文：检测方式是尝试用 OpenMP 参数编译一个空输入，成功才追加相关 flag。
# OpenMP makes the code a lot faster so I advise installing it
# 中文：OpenMP 对 CPU 训练很重要，建议安装。
# e.g. on MacOS: brew install libomp
# 中文：macOS 可以用 Homebrew 安装：`brew install libomp`。
# e.g. on Ubuntu: sudo apt-get install libomp-dev
# 中文：Ubuntu 可以安装：`sudo apt-get install libomp-dev`。
# later, run the program by prepending the number of threads, e.g.: OMP_NUM_THREADS=8 ./gpt2
# 中文：运行时可用 `OMP_NUM_THREADS=8 ./train_gpt2` 指定线程数。
# First, check if NO_OMP is set to 1, if not, proceed with the OpenMP checks
# 中文：如果用户传 `NO_OMP=1`，就跳过 OpenMP 检测并禁用 OpenMP。
ifeq ($(NO_OMP), 1)
  # 用户手动禁用 OpenMP。
  $(info OpenMP is manually disabled)
else
  # Windows 的 OpenMP 参数已经在 MSVC CFLAGS 中处理；这里只处理非 Windows。
  ifneq ($(OS), Windows_NT)
  # Detect if running on macOS or Linux
  # 中文：检测当前是 macOS 还是 Linux，因为 OpenMP 安装路径不同。
    ifeq ($(SHELL_UNAME), Darwin)
      # Check for Homebrew's libomp installation in different common directories
      # 中文：macOS 下检查 Homebrew 常见安装路径。
      ifeq ($(shell [ -d /opt/homebrew/opt/libomp/lib ] && echo "exists"), exists)
        # macOS with Homebrew on ARM (Apple Silicon)
        # 中文：Apple Silicon Mac 的 Homebrew 默认在 /opt/homebrew。
        CFLAGS += -Xclang -fopenmp -DOMP
        # 链接时加入 libomp 的库路径。
        LDFLAGS += -L/opt/homebrew/opt/libomp/lib
        # 链接 OpenMP runtime 库 libomp。
        LDLIBS += -lomp
        # 编译时加入 libomp 头文件路径。
        INCLUDES += -I/opt/homebrew/opt/libomp/include
        # 打印 OpenMP 找到提示。
        $(info ✓ OpenMP found)
      else ifeq ($(shell [ -d /usr/local/opt/libomp/lib ] && echo "exists"), exists)
        # macOS with Homebrew on Intel
        # 中文：Intel Mac 的 Homebrew 常见路径是 /usr/local。
        CFLAGS += -Xclang -fopenmp -DOMP
        # 链接 Intel Homebrew 的 libomp 库路径。
        LDFLAGS += -L/usr/local/opt/libomp/lib
        # 链接 OpenMP runtime 库 libomp。
        LDLIBS += -lomp
        # 编译时加入 libomp 头文件路径。
        INCLUDES += -I/usr/local/opt/libomp/include
        # 打印 OpenMP 找到提示。
        $(info ✓ OpenMP found)
      else
        # macOS 上没有找到 libomp，CPU 版本仍可编译，但不会启用 OpenMP 多线程。
        $(info ✗ OpenMP not found)
      endif
    else
      # Check for OpenMP support in GCC or Clang on Linux
      # 中文：Linux 下尝试用 `-fopenmp` 预处理空输入，成功代表编译器支持 OpenMP。
      ifeq ($(shell echo | $(CC) -fopenmp -x c -E - > /dev/null 2>&1; echo $$?), 0)
        # Linux 下 GCC/Clang OpenMP 通常使用 -fopenmp，并定义 OMP 宏。
        CFLAGS += -fopenmp -DOMP
        # Linux 下常用 GNU OpenMP runtime libgomp。
        LDLIBS += -lgomp
        # 打印 OpenMP 找到提示。
        $(info ✓ OpenMP found)
      else
        # Linux 下 OpenMP 不可用，CPU 版本仍可编译，但不会启用多线程。
        $(info ✗ OpenMP not found)
      endif
    endif
  endif
endif

# Check if NCCL is available, include if so, for multi-GPU training
# 中文：检测 NCCL；NCCL 用于 CUDA 多 GPU 训练时做 GPU 间通信。
ifeq ($(NO_MULTI_GPU), 1)
  # 用户手动禁用多 GPU/NCCL。
  $(info → Multi-GPU (NCCL) is manually disabled)
else
  # Windows 之外再检测 NCCL；此处主要面向 Linux。
  ifneq ($(OS), Windows_NT)
    # Detect if running on macOS or Linux
    # 中文：区分 macOS 和 Linux，因为 macOS 不支持 CUDA 多 GPU。
    ifeq ($(SHELL_UNAME), Darwin)
      # macOS 上没有 NVIDIA CUDA 多 GPU 支持，跳过 NCCL。
      $(info ✗ Multi-GPU on CUDA on Darwin is not supported, skipping NCCL support)
    else ifeq ($(shell dpkg -l | grep -q nccl && echo "exists"), exists)
      # Linux 下通过 dpkg 检测是否安装了 NCCL 包。
      $(info ✓ NCCL found, OK to train with multiple GPUs)
      # 定义 MULTI_GPU 宏，让源码启用多 GPU 分支。
      NVCC_FLAGS += -DMULTI_GPU
      # 链接 NCCL 库。
      NVCC_LDLIBS += -lnccl
    else
      # 没找到 NCCL，就禁用多 GPU 支持并给出安装提示。
      $(info ✗ NCCL is not found, disabling multi-GPU support)
      $(info ---> On Linux you can try install NCCL with `sudo apt install libnccl2 libnccl-dev`)
    endif
  endif
endif

# Attempt to find and include OpenMPI on the system
# 中文：尝试检测 OpenMPI；多节点/多进程训练可用 MPI 交换 NCCL 初始化信息。
OPENMPI_DIR ?= /usr/lib/x86_64-linux-gnu/openmpi
# OpenMPI 库文件目录。
OPENMPI_LIB_PATH = $(OPENMPI_DIR)/lib/
# OpenMPI 头文件目录。
OPENMPI_INCLUDE_PATH = $(OPENMPI_DIR)/include/
ifeq ($(NO_USE_MPI), 1)
  # 用户手动禁用 MPI。
  $(info → MPI is manually disabled)
else ifeq ($(shell [ -d $(OPENMPI_LIB_PATH) ] && [ -d $(OPENMPI_INCLUDE_PATH) ] && echo "exists"), exists)
  # 如果 OpenMPI lib/include 目录都存在，就启用 MPI。
  $(info ✓ MPI enabled)
  # 追加 MPI 头文件路径给 CUDA 编译器。
  NVCC_INCLUDES += -I$(OPENMPI_INCLUDE_PATH)
  # 追加 MPI 库路径给 CUDA 链接器。
  NVCC_LDFLAGS += -L$(OPENMPI_LIB_PATH)
  # 链接 mpi 库。
  NVCC_LDLIBS += -lmpi
  # 定义 USE_MPI 宏，让源码启用 MPI 分支。
  NVCC_FLAGS += -DUSE_MPI
else
  # 找不到 OpenMPI，打印提示；单机单 GPU/部分多 GPU场景仍可继续。
  $(info ✗ MPI not found)
endif

# Precision settings, default to bf16 but ability to override
# 中文：CUDA 主线默认使用 BF16，也可以用 `make PRECISION=FP32|FP16|BF16 ...` 覆盖。
PRECISION ?= BF16

# 允许的精度枚举。
VALID_PRECISIONS := FP32 FP16 BF16

# 如果用户传入的 PRECISION 不在允许列表中，就报错终止。
ifeq ($(filter $(PRECISION),$(VALID_PRECISIONS)),)
  $(error Invalid precision $(PRECISION), valid precisions are $(VALID_PRECISIONS))
endif

# 根据 PRECISION 生成传给源码的宏定义。
ifeq ($(PRECISION), FP32)
  # FP32 全精度路径。
  PFLAGS = -DENABLE_FP32
else ifeq ($(PRECISION), FP16)
  # FP16 半精度路径。
  PFLAGS = -DENABLE_FP16
else
  # 默认 BF16 路径。
  PFLAGS = -DENABLE_BF16
endif

# PHONY means these targets will always be executed
# 中文：.PHONY 表示这些 target 不是实际文件名；即使同名文件存在，make 也会执行对应规则。
.PHONY: all train_gpt2 test_gpt2 train_gpt2cu test_gpt2cu train_gpt2fp32cu test_gpt2fp32cu profile_gpt2cu

# Add targets
# 中文：默认构建目标先包含 CPU 训练程序和 CPU 测试程序。
TARGETS = train_gpt2 test_gpt2

# Conditional inclusion of CUDA targets
# 中文：只有检测到 nvcc 时，才把 CUDA 相关 target 加入默认构建列表。
ifeq ($(NVCC),)
    # 没有 nvcc，跳过 GPU/CUDA target。
    $(info ✗ nvcc not found, skipping GPU/CUDA builds)
else
    # 找到 nvcc，加入 CUDA 训练/测试/profile target。
    $(info ✓ nvcc found, including GPU/CUDA support)
    TARGETS += train_gpt2cu test_gpt2cu train_gpt2fp32cu test_gpt2fp32cu $(NVCC_CUDNN)
endif

# 打印分隔线，让 make 输出里的平台检测结果更清楚。
$(info ---------------------------------------------)

# 默认 target：执行 `make` 等价于构建 TARGETS 中的所有目标。
all: $(TARGETS)

# CPU GPT-2 训练程序：源文件是 train_gpt2.c。
train_gpt2: train_gpt2.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LDFLAGS) $^ $(LDLIBS) $(OUTPUT_FILE)

# CPU GPT-2 正确性测试程序：源文件是 test_gpt2.c。
test_gpt2: test_gpt2.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LDFLAGS) $^ $(LDLIBS) $(OUTPUT_FILE)

# cuDNN attention object：启用 USE_CUDNN=1 时需要单独编译 cudnn_att.cpp。
$(NVCC_CUDNN): llmc/cudnn_att.cpp
	$(NVCC) -c $(NVCC_FLAGS) $(PFLAGS) $^ $(NVCC_INCLUDES) -o $@

# CUDA GPT-2 主线训练程序：依赖 train_gpt2.cu，以及可选的 cuDNN object。
train_gpt2cu: train_gpt2.cu $(NVCC_CUDNN)
	$(NVCC) $(NVCC_FLAGS) $(PFLAGS) $^ $(NVCC_LDFLAGS) $(NVCC_INCLUDES) $(NVCC_LDLIBS) $(CUDA_OUTPUT_FILE)

# 旧版/教学用 FP32 CUDA 训练程序：源文件是 train_gpt2_fp32.cu。
train_gpt2fp32cu: train_gpt2_fp32.cu
	$(NVCC) $(NVCC_FLAGS) $^ $(NVCC_LDFLAGS) $(NVCC_INCLUDES) $(NVCC_LDLIBS) $(CUDA_OUTPUT_FILE)

# CUDA GPT-2 正确性测试程序：依赖 test_gpt2.cu，以及可选的 cuDNN object。
test_gpt2cu: test_gpt2.cu $(NVCC_CUDNN)
	$(NVCC) $(NVCC_FLAGS) $(PFLAGS) $^ $(NVCC_LDFLAGS) $(NVCC_INCLUDES) $(NVCC_LDLIBS) $(CUDA_OUTPUT_FILE)

# 旧版/教学用 FP32 CUDA 测试程序：源文件是 test_gpt2_fp32.cu。
test_gpt2fp32cu: test_gpt2_fp32.cu
	$(NVCC) $(NVCC_FLAGS) $^ $(NVCC_LDFLAGS) $(NVCC_INCLUDES) $(NVCC_LDLIBS) $(CUDA_OUTPUT_FILE)

# CUDA profile 版本：加上 -lineinfo，方便 Nsight 等工具把性能信息映射回源码行。
profile_gpt2cu: profile_gpt2.cu $(NVCC_CUDNN)
	$(NVCC) $(NVCC_FLAGS) $(PFLAGS) -lineinfo $^ $(NVCC_LDFLAGS) $(NVCC_INCLUDES) $(NVCC_LDLIBS)  $(CUDA_OUTPUT_FILE)

# 清理构建产物：删除可执行文件和 build 目录下的 object 文件。
clean:
	$(REMOVE_FILES) $(TARGETS)
	$(REMOVE_BUILD_OBJECT_FILES)
