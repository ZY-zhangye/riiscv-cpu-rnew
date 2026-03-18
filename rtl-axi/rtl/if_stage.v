/*
 * ============================================================================
 * IF (Instruction Fetch) Stage - 取指阶段
 * ============================================================================
 * 
 * 功能概述：
 *   负责向存储器发起指令读请求，接收返回数据，并将指令交付给ID(译码)阶段。
 *
 * 核心设计原则：
 *   1. 单在途请求(req_pending): 同时最多一条未返回的取指请求
 *   2. 一级缓冲(fs_inst/fs_pc): 当ID不接收时暂存返回的指令
 *   3. 条件旁路: 返回当拍直接给ID(避免多打一拍延迟)
 *   4. 重定向保护: 分支/异常后丢弃旧路径在途响应
 *
 * 工作流程：
 *   - 无在途请求 + 缓冲空 -> issue_fire=1 发新请求
 *   - 返回到来 + ID可接收 + 缓冲空 -> 旁路给ID(同拍)
 *   - 返回到来 + ID背压 -> 进缓冲(等下拍再送)
 *   - 缓冲有数据 -> 缓冲优先输出给ID
 *   - 分支/异常 -> 如有旧在途请求 -> 标记准备丢弃该响应
 *
 * ============================================================================
 */
`include "defines.v"
module if_stage (
    input wire clk,
    input wire rst_n,
    //取指端口
    output reg [31:0] pc_out,
    input wire [31:0] inst_in,
    output reg inst_ren,
    input wire inst_valid,
    //与译码阶段的握手信号
    input wire ds_allowin,
    output wire fs_to_ds_valid,
    //译码阶段总线
    output wire [`FS_TO_DS_BUS_WD-1:0] if_id_bus_out,
    //分支跳转
    input wire [31:0] br_target,
    input wire br_jmp_flag,
    //异常相关信号
    output wire [5:0] exception_code_fd,
    output wire [31:0] exception_mtval_fd,
    input wire exception_flag,
    input wire [31:0] exception_addr
);

    localparam nop_inst = 32'h0000_0013; // addi x0, x0, 0

    // ========== PC 生成与请求发射 ==========
    wire [31:0] issue_pc;           // 本拍要发出的请求PC (组合逻辑)
    reg [31:0] req_pc;              // 寄存最近发出的请求PC (用于顺序地址计算)
    reg req_pending;                // 标志: 当前是否有在途请求(已发未返)

    // ========== 缓冲管理 ==========
    // IF内部暂存返回指令的一级缓冲，用于应对ID背压
    reg fs_valid;                   // 缓冲满标志(=1时缓冲有数据)
    reg [31:0] fs_pc;               // 缓冲内PC
    reg [31:0] fs_inst;             // 缓冲内指令
    wire fs_valid_next;             // 下一拍缓冲满标志(组合逻辑)
    wire fs_pop;                    // 缓冲当拍出队(下游接收)
    wire fs_push;                   // 缓冲当拍入队(返回需存)

    // ========== 通路选择与输出 ==========
    wire [31:0] fs_out_pc;          // 送给ID的PC(缓冲优先，否则旁路)
    wire [31:0] fs_out_inst;        // 送给ID的指令(缓冲优先，否则旁路)
    wire fs_bypass_valid;           // 旁路条件满足(返回当拍直接给ID)

    // ========== 返回响应处理 ==========
    wire inst_resp_valid;           // 有返回到来(req_pending && inst_valid)
    wire inst_resp_commit;          // 返回可提交(不是旧路径需丢弃)
    wire inst_resp_kill;            // 返回需丢弃(旧路径或旧重定向)
    
    // ========== 重定向与旧响应丢弃 ==========
    wire redirect_now;              // 本拍发生重定向(分支/异常)
    wire redirect_event;            // 重定向上升沿事件(仅触发一拍)
    reg redirect_now_d;             // 上一拍redirect_now(用于检测沿)
    reg drop_resp_pending;          // 标志: 有一条旧响应待丢弃

    //由于exception_flag是外部输入的电平信号，可能持续多拍，因此需要一个寄存器来记录上拍的状态，以便检测重定向事件(沿)。
    reg exception_flag_reg;
    reg [31:0] exception_addr_reg;
    always @ (*) begin
        if (!rst_n) begin
            exception_flag_reg = 1'b0;
            exception_addr_reg = 32'b0;
        end else if (exception_flag) begin
            exception_flag_reg = 1'b1;
            exception_addr_reg = exception_addr;
        end else if (fs_to_ds_valid) begin
            // 当指令成功送出时，清除异常标志(假设异常处理器会在ID阶段接收并处理异常)
            exception_flag_reg = 1'b0;
            exception_addr_reg = 32'b0;
        end else begin
            // 其他情况保持原值
            exception_flag_reg = exception_flag_reg;
            exception_addr_reg = exception_addr_reg;
        end
    end

    // ========== PC 计算逻辑 ==========
    // 下一拍要发的请求PC，优先级：异常 > 分支 > 顺序
    // 重要：顺序PC = req_pc+4，不用fs_pc
    //   原因：fs_pc代表当前输出给ID的指令地址，可能因旁路/背压与最新请求不同；
    //        req_pc始终记录"最近一次发出的请求"，是PC计算的正确参考
    assign issue_pc = exception_flag_reg ? exception_addr_reg :
                      br_jmp_flag ? br_target :
                      (req_pc + 32'd4);

    // ========== 握手与返回有效性判定 ==========
    wire fs_ready_go = 1'b1; // IF阶段总是准备好(传播性强，不主动暂停)
    
    assign redirect_now = exception_flag_reg || br_jmp_flag; // 电平：本拍发生重定向
    assign redirect_event = redirect_now && !redirect_now_d; // 事件：重定向上升沿(仅1拍脉冲)
    
    assign inst_resp_valid = req_pending && inst_valid; // 有返回(在途请求 AND 返回数据有效)
    
    // ========== 返回响应可提交判定(正确性关键) ==========
    // inst_resp_kill = 1时，该响应不能旁路/入缓冲，应被丢弃
    // 触发条件：
    //   1. drop_resp_pending=1: 正在等待丢弃一条旧响应
    //   2. redirect_event=1 AND req_pending=1: 刚发生重定向且有在途请求
    // 注意：用redirect_event而不是redirect_now电平
    //   原因：redirect_now可能持续高电平，会误杀多条返回；
    //        redirect_event仅单拍脉冲，只准确杀掉一条旧响应
    assign inst_resp_kill = inst_resp_valid && (drop_resp_pending || (redirect_event && req_pending));
    assign inst_resp_commit = inst_resp_valid && !inst_resp_kill; // 可提交 = 有返回且不需丢弃
    
    // ========== 旁路条件与输出有效 ==========
    // 旁路的前提：缓冲为空 + 返回可提交(不是旧路径)
    // 目的：消除多打一拍的延迟
    assign fs_bypass_valid = !fs_valid && inst_resp_commit;
    
    // IF->ID握手有效：缓冲有数据 OR 旁路成立 
    // (fs_ready_go始终=1，只在这里用作形式上的协议完整性)
    assign fs_to_ds_valid = (fs_valid || fs_bypass_valid) && fs_ready_go;

    // ========== 输出数据选择(缓冲优先) ==========
    // 原则：缓冲有数据用缓冲，缓冲空用旁路返回
    // 目的：保证同一时刻数据源唯一、不出现从缓冲和旁路的混杂
    assign fs_out_pc = fs_valid ? fs_pc : req_pc;    // req_pc存储的是该条请求的PC
    assign fs_out_inst = fs_valid ? fs_inst : inst_in; // 当拍旁路用存储器返回

    // ========== 缓冲管理逻辑 ==========
    // pop: 缓冲当拍出队(有数据 + 下游接收)
    assign fs_pop = fs_valid && ds_allowin;
    
    // push: 返回当拍入缓冲
    //   条件：返回可提交 + 不满足旁路直通
    //   不旁路情况举例：ID背压(ds_allowin=0) 或 缓冲里还有货
    //   设计目的：避免返回丢失，同时尽量减少缓冲进出
    assign fs_push = inst_resp_commit && !(fs_bypass_valid && ds_allowin);
    
    // fs_valid下一拍值：缓冲保留 OR 缓冲进新数据
    assign fs_valid_next = (fs_valid && !fs_pop) || fs_push;

    // ========== 请求发射控制(关键的流量控制) ==========
    // 准许发新请求的条件(issue_fire)：
    //   1. 在途可清空：无在途请求(!req_pending) OR 本拍刚收到返回(inst_resp_valid)
    //   2. 缓冲有空间：本拍状态收敛后缓冲仍为空(!fs_valid_next)
    //
    // 为什么需要两个条件？
    //   条件1：保证请求-响应配对 (不会让新请求和旧响应错配)
    //   条件2：保证缓冲不会溢出 (有返回来但无处可放)
    //
    // 示例流：
    //   Cycle N: issue_fire=1 -> 发出请求，req_pending=1  
    //   Cycle N+k: inst_valid=1 -> 返回到来，inst_resp_valid=1  
    //   同一Cycle: fs_push=1 -> 数据入缓, fs_valid_next=1
    //   同一Cycle: issue_fire仍可能=1 (因为inst_resp_valid满足条件1)
    //   -> 立即发下一拍请求，流水继续
    wire issue_fire = (inst_resp_valid || !req_pending) && !fs_valid_next;

    // ========== 时序逻辑 (所有状态更新在时钟上升沿) ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位初值设置
            fs_valid <= 1'b0;           // 缓冲初始空
            fs_pc <= 32'hffff_fffc;     // PC初值-4，+4后是0
            fs_inst <= nop_inst;        // 指令初值为NOP
            req_pc <= 32'hffff_fffc;    // 记录PC初值-4
            req_pending <= 1'b0;        // 初无在途请求
            drop_resp_pending <= 1'b0;  // 初无待丢弃响应
            redirect_now_d <= 1'b0;     // 初无重定向
            pc_out <= 32'h0;            // 初请求地址为0
            inst_ren <= 1'b0;           // 初无请求脉冲
        end else begin
            // ========== 每拍更新: 重定向历史用于沿检测 ==========
            redirect_now_d <= redirect_now; // 滞后一拍记录重定向电平
            inst_ren <= 1'b0; // 默认无请求脉冲(仅在issue_fire时拉高)

            // ========== 更新1: 缓冲有效位状态转移 ==========
            fs_valid <= fs_valid_next; // 根据push/pop结果更新满标志

            // ========== 更新2: 缓冲数据(当需要入缓时) ==========
            // 时机：返回到来 + 不能旁路给ID + 下游背压或缓冲非空
            if (fs_push) begin
                fs_inst <= inst_in; // 获取本拍存储器返回的指令
                fs_pc <= req_pc;    // 关键：用req_pc而不是inst_in的隐含PC
                                    // 原因：req_pc是发请求时记录的确定值，不受其他路径影响
            end

            // ========== 更新3: 旧响应丢弃标记(单在途版epoch思想) ==========
            // 处理场景：分支/异常后如有旧路径在途请求 -> 该响应回来时应丢弃
            //
            // 状态转移：
            //   - 重定向发生(沿) + 当前有在途 -> drop_resp_pending置1(等待丢1拍)
            //   - 任意返回到来 -> drop_resp_pending清0(已处理或已返回)
            if (inst_resp_valid) begin
                drop_resp_pending <= 1'b0; // 返回处理完(无论提交还是丢弃)，清标记
            end else if (redirect_event && req_pending) begin
                drop_resp_pending <= 1'b1; // 新重定向 + 有旧在途 -> 标记待丢
            end

            // ========== 更新4: 在途请求标记状态转移 ==========
            // req_pending维护"当前是否有未返回的请求"
            // 更新公式：保留旧在途 OR 发出新请求
            req_pending <= (req_pending && !inst_resp_valid) || issue_fire;
            // 第一项 (req_pending && !inst_resp_valid)：
            //   如果旧请求还未返回，这一项=1，req_pending继续保持
            // 第二项 issue_fire：
            //   如果本拍发出新请求，这一项=1，req_pending被置位
            // 效果：req_pending总是反映"是否有请求在途"

            // ========== 更新5: 当拍发射新请求 ==========
            // 仅当issue_fire=1时，才能发出新的取指请求
            if (issue_fire) begin
                pc_out <= issue_pc;  // 送存储器的请求地址(运算结果)
                inst_ren <= 1'b1;    // 单拍脉冲表示"本拍发请求"
                req_pc <= issue_pc;  // 记录本拍请求的PC(用于后续顺序地址计算)
            end

        end
    end

    // ========== 输出总线与异常信息 ==========
    // IF->ID 指令总线：{指令, PC}
    assign if_id_bus_out = {fs_out_inst, fs_out_pc};

    // 异常检测：地址对齐异常(RISC-V指令必须4字节对齐)
    // 触发：当send数据有效 + PC[1:0] != 2'b00
    // 原理：fs_to_ds_valid代表"真实送出指令的拍"，此时检测PC合法性
    wire exception_iam = fs_to_ds_valid && (fs_out_pc[1:0] != 2'b00);
    
    // 异常码编码：
    //   6'b100000 (0x20) = 指令地址不对齐异常
    //   6'b000000 (0x00) = 无异常
    assign exception_code_fd = exception_iam ? 6'b100000 : 6'b000000;
    
    // 异常地址：记录触发异常时的PC值(用于异常处理/调试)
    assign exception_mtval_fd = fs_out_pc;

endmodule

