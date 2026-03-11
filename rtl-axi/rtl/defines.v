`define FS_TO_DS_BUS_WD 64 // fs_inst[31:0], fs_pc[31:0]
`define DS_TO_ES_BUS_WD 220 // br_type由3位编码扩展为6位one-hot，总线宽由217增至220
`define ES_TO_MS_BUS_WD 123
`define MS_TO_WS_BUS_WD 70