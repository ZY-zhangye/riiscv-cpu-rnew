`define FS_TO_DS_BUS_WD 64 // fs_inst[31:0], fs_pc[31:0]
`define DS_TO_ES_BUS_WD 220 // br_type由3位编码扩展为6位one-hot，总线宽由217增至220
`define ES_TO_MS_BUS_WD 123
`define MS_TO_WS_BUS_WD 70



//IO口地址以及相关含义
//UART地址以及相关含义
//基地址
`define UART_BASE_ADDR 16'h8000
`define UART_RT_DATA 16'h0000 //UART数据寄存器地址
`define UART_RT_STATUS 16'h0004 //UART状态寄存器地址
`define UART_RT_CTRL 16'h0008 //UART控制寄存器地址
`define UART_RT_BAUD 16'h000C //UART波特率寄存器地址