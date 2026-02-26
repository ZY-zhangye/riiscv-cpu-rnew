# RIISCV-CPU-RNEW

轻量级五级流水 RV32IM（含 CSR/异常）的教学/验证用 CPU 实现，带最小外设桥接与批量指令集回归脚本，可直接在 ModelSim / QuestaSim 上运行 riscv-tests。

## 核心特性
- 五级流水：IF/ID/EX/MEM/WB，握手信号控制停顿与冲刷。
- 数据前递与冒险处理：EX/MEM 阶段结果前递到 ID，避免常见 RAW 冒险。
- 分支/跳转：EX 阶段计算 `br_target` 与 `br_taken`，执行错误时冲刷流水线。
- 访存接口：字节/半字/字写使能，未对齐访问检测；独立指令/数据 RAM，通过 `bridge` 可扩展外设（示例含 LED）。
- CSR 与异常：`regfiles_csr` 管理 CSR，ID/EX/MEM 逐级传递异常编码与 `mtval`，支持取指/访存/跳转对齐异常。
- 调试信号：WB 阶段导出 `debug_wb_pc`、`debug_wb_rf_wen/wnum/wdata` 与 `debug_data`（x10）。

## 目录概览
- `rtl/`：顶层 `top.v`、流水段、寄存器堆、CSR、RAM、桥接等模块。
- `test/`：`tb_top.v` 测试平台，内置波形 dump 与简单通过判定。
- `hex/`：riscv-tests 生成的指令/数据镜像，`rv32-p-riscv.hex` 由批处理脚本覆盖。
- `results/`：批量回归的日志输出（每条指令一个 txt）。
- `run_all.bat`：批量编译+仿真 RV32UI/MI/UM 指令集并判分。
- `clean.bat`：清理解构/临时文件（若有）。

## 仿真环境依赖
- ModelSim 或 QuestaSim（已使用 `vlog`/`vsim` 命令）。
- Windows 环境（批处理路径使用反斜杠）。

## 快速开始
1) 安装 ModelSim/QuestaSim 并在终端能直接调用 `vlog`、`vsim`。
2) 运行批量回归（默认覆盖 `hex/riscv-tests/rv32-p-riscv.hex`）：
   - 双击 `run_all.bat` 或在命令行运行它。
   - 通过后 `results/` 下对应指令 txt 会包含 `Test passed.`。
3) 单条用例手动仿真（示例：`rv32ui-p-add`）：
   - 将目标 hex 拷贝为 `hex\riscv-tests\rv32-p-riscv.hex`。
   - 在工程根目录执行：先 `vlog -sv rtl/*.v test/*.v`，再 `vsim -do "run -all" tb_top`。
4) 观察波形：`tb_top.v` 已启用 `$dumpfile("tb_top.vcd")`，可在仿真后用波形查看器打开。

## 配置要点
- `test/tb_top.v` 中 `MEM_HEX_PATH` 定义当前仿真镜像路径，批处理会自动替换目标文件。
- `rtl/my_cpu.v` 的参数 `MEM_HEX_PATH` 控制指令/数据 RAM 预加载文件，若需自定义程序可修改此参数或覆盖 hex。
- I/O 示例：向地址高 4 位为 `0x8` 的写访问会驱动 4bit `led`。

## 常见问题
- **找不到 vlog/vsim**：确认已将 ModelSim/QuestaSim `bin` 目录加入 PATH。
- **仿真超时**：`tb_top` 设有 25,000ns 超时，若程序更长可调整 `#25000`；也可在测试结束条件中修改 `debug_wb_pc` 判定地址。
- **新测试用例**：将新的 `.hex` 放入 `hex/riscv-tests/`，并在 `run_all.bat` 的指令列表中追加名称即可。

## 参考信号
- 指令侧：`imem_addr`/`imem_rdata`/`imem_ren`
- 数据侧：`dmem_addr`/`dmem_wdata`/`dmem_wen`/`dmem_rdata`/`dmem_en`
- 调试：`debug_wb_pc`、`debug_wb_rf_wen`、`debug_wb_rf_wnum`、`debug_wb_rf_wdata`、`debug_data` (x10)

##支持指令
UI_INSTS=(sw lw add addi sub and andi or ori xor xori 
          sll srl sra slli srli srai slt slti sltu sltiu 
          beq bne blt bge bltu bgeu jal jalr lui auipc lh lhu sh sb lb lbu)
MI_INSTS=(csr scall sbreak ma_fetch)*/
UM_INSTS=(mul mulh mulhu mulhsu)

祝仿真顺利，测试全绿！
