set partNumber $::env(XILINX_PART)
set boardName  $::env(XILINX_BOARD)

set ipName float32_mac

create_project $ipName . -force -part $partNumber
set_property board_part $boardName [current_project]

create_ip -name floating_point -vendor xilinx.com -library ip -module_name $ipName

# set_property -dict [list CONFIG.DATA_WIDTH {64} CONFIG.ID_WIDTH {5} CONFIG.MEM_DEPTH {65536} CONFIG.READ_LATENCY {1} CONFIG.SINGLE_PORT_BRAM {1}] [get_ips $ipName]
set_property -dict [list CONFIG.A_Precision_Type {Single} CONFIG.C_Latency {19} CONFIG.Result_Precision_Type {Single} CONFIG.Operation_Type {FMA} CONFIG.Add_Sub_Value {Add} CONFIG.Flow_Control {NonBlocking} CONFIG.C_A_Exponent_Width {8} CONFIG.C_A_Fraction_Width {24} CONFIG.C_Result_Exponent_Width {8} CONFIG.C_Result_Fraction_Width {24}] [get_ips $ipName]

# CONFIG.ACLK_INTF.FREQ_HZ	10000000
# CONFIG.ACLK_INTF.INSERT_VIP	0
# CONFIG.ARESETN_INTF.INSERT_VIP	0
# CONFIG.A_Precision_Type	Single
# CONFIG.A_TUSER_Width	1
# CONFIG.Add_Sub_Value	Add
# CONFIG.Axi_Optimize_Goal	Resources
# CONFIG.B_TUSER_Width	1
# CONFIG.C_A_Exponent_Width	8
# CONFIG.C_A_Fraction_Width	24
# CONFIG.C_Accum_Input_Msb	32
# CONFIG.C_Accum_Lsb	-31
# CONFIG.C_Accum_Msb	32
# CONFIG.C_BRAM_Usage	No_Usage
# CONFIG.C_Compare_Operation	Programmable
# CONFIG.C_Has_ACCUM_INPUT_OVERFLOW	false
# CONFIG.C_Has_ACCUM_OVERFLOW	false
# CONFIG.C_Has_DIVIDE_BY_ZERO	false
# CONFIG.C_Has_INVALID_OP	false
# CONFIG.C_Has_OVERFLOW	false
# CONFIG.C_Has_UNDERFLOW	false
# CONFIG.C_Latency	19
# CONFIG.C_Mult_Usage	Full_Usage
# CONFIG.C_Optimization	Speed_Optimized
# CONFIG.C_Rate	1
# CONFIG.C_Result_Exponent_Width	8
# CONFIG.C_Result_Fraction_Width	24
# CONFIG.C_TUSER_Width	1
# CONFIG.Component_Name	float32_mac
# CONFIG.Flow_Control	NonBlocking
# CONFIG.Has_ACLKEN	false
# CONFIG.Has_ARESETn	false
# CONFIG.Has_A_TLAST	false
# CONFIG.Has_A_TUSER	false
# CONFIG.Has_B_TLAST	false
# CONFIG.Has_B_TUSER	false
# CONFIG.Has_C_TLAST	false
# CONFIG.Has_C_TUSER	false
# CONFIG.Has_OPERATION_TLAST	false
# CONFIG.Has_OPERATION_TUSER	false
# CONFIG.Has_RESULT_TREADY	false
# CONFIG.M_AXIS_RESULT.INSERT_VIP	0
# CONFIG.Maximum_Latency	true
# CONFIG.OPERATION_TUSER_Width	1
# CONFIG.Operation_Type	FMA
# CONFIG.RESULT_TLAST_Behv	Null
# CONFIG.Result_Precision_Type	Single
# CONFIG.S_AXIS_A.INSERT_VIP	0
# CONFIG.S_AXIS_B.INSERT_VIP	0
# CONFIG.S_AXIS_C.INSERT_VIP	0
# CONFIG.S_AXIS_OPERATION.INSERT_VIP	0

generate_target {instantiation_template} [get_files ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
generate_target all [get_files  ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
create_ip_run [get_files -of_objects [get_fileset sources_1] ./$ipName.srcs/sources_1/ip/$ipName/$ipName.xci]
launch_run -jobs 8 ${ipName}_synth_1
wait_on_run ${ipName}_synth_1
