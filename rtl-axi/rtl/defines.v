`define FS_TO_DS_BUS_WD 64 // fs_inst[31:0], fs_pc[31:0]
`define DS_TO_ES_BUS_WD 220 // br_type由3位编码扩展为6位one-hot，总线宽由217增至220
`define ES_TO_MS_BUS_WD 123
`define MS_TO_WS_BUS_WD 70

//debug开关
`define DEBUG_EN



//IO口地址以及相关含义
//PLIC地址以及相关含义
//基地址
`define PLIC_BASE_ADDR 16'h8000
`define PLIC_PRIORITY_NUM 16 //PLIC支持的中断源数量
`define PLIC_PRIORITY_WD 8 //每个中断源优先级寄存器宽度
`define PLIC_PENDING_WD 16 //PLIC待处理寄存器宽度，每位对应一个中断源
`define PLIC_ENABLE_WD 16 //PLIC使能寄存器宽度，每位对应一个中断源
`define PLIC_THRESHOLD_WD 8 //PLIC阈值寄存器宽度
`define PLIC_CLAIM_WD 16 //PLIC请求寄存器宽度
`define PLIC_PRIORITY_OFFSET 16'h0000 //PLIC优先级寄存器基地址偏移
`define PLIC_PENDING_OFFSET 16'h1000 //PLIC待处理寄存器基地址偏移
`define PLIC_ENABLE_OFFSET 16'h2000 //PLIC使能寄存器基地址偏移
`define PLIC_THRESHOLD_OFFSET 16'h2004 //PLIC阈值寄存器基地址偏移
`define PLIC_CLAIM_OFFSET 16'h2008 //PLIC请求寄存器基地址偏移
//PLIC中断号定义
`define UART_RX_INT_ID 0 //UART接收中断号
`define UART_TX_INT_ID 1 //UART发送中断号
`define TIMER_INT_ID 2 //定时器中断号

//UART地址以及相关含义
//基地址
`define UART_BASE_ADDR 16'h8001
`define UART_RT_DATA 16'h0000 //UART数据寄存器地址
`define UART_RT_STATUS 16'h0004 //UART状态寄存器地址
`define UART_RT_CTRL 16'h0008 //UART控制寄存器地址
`define UART_RT_BAUD 16'h000C //UART波特率寄存器地址
//定时器地址以及相关含义
//基地址
`define TIMER_BASE_ADDR 16'h8002
`define TIMER_LOAD 16'h0000 //定时器装载寄存器地址
`define TIMER_VALUE 16'h0004 //定时器当前值寄存器地址 只读
`define TIMER_CTRL 16'h0008 //定时器控制寄存器地址
`define TIMER_INTCLR 16'h000C //定时器中断清除寄存器地址 写1清除中断
`define TIMER_PRESCALER 16'h0010 //定时器预分频寄存器地址

//LEDS地址以及相关含义
`define LEDS_BASE_ADDR 16'h8003

