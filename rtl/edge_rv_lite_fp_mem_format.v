`timescale 1ns/1ps

// Converts the physical FP32 FPR payload to/from the scalar FP memory formats.
module edge_rv_lite_fp_mem_format (
  input  wire [2:0]  funct3,
  input  wire [63:0] load_value,
  input  wire [31:0] store_fp32,
  output reg  [31:0] load_fp32,
  output reg  [63:0] store_value
);
  function [31:0] fp16_to_fp32;
    input [15:0] value;
    integer bit_index, shift;
    reg [9:0] frac;
    reg [7:0] exponent;
    reg found;
    begin
      if (value[14:10] == 0) begin
        if (value[9:0] == 0) fp16_to_fp32 = {value[15],31'b0};
        else begin
          shift=0; found=0;
          for(bit_index=9;bit_index>=0;bit_index=bit_index-1)
            if(!found&&value[bit_index]) begin shift=9-bit_index; found=1; end
          frac=value[9:0]<<shift; exponent=8'd112-shift;
          fp16_to_fp32={value[15],exponent,frac[8:0],14'b0};
        end
      end else if(value[14:10]==5'h1f)
        fp16_to_fp32=value[9:0]==0?{value[15],8'hff,23'b0}:32'h7fc00000;
      else fp16_to_fp32={value[15],value[14:10]+8'd112,value[9:0],13'b0};
    end
  endfunction

  function [31:0] bf16_to_fp32;
    input [15:0] value;
    begin
      bf16_to_fp32=(value[14:7]==8'hff&&value[6:0]!=0)?
        32'h7fc00000:{value,16'b0};
    end
  endfunction

  function [31:0] fp8_e5m2_to_fp32;
    input [7:0] value;
    begin
      if(value[6:2]==0) begin
        case(value[1:0])
          0: fp8_e5m2_to_fp32={value[7],31'b0};
          1: fp8_e5m2_to_fp32={value[7],8'd111,23'b0};
          2: fp8_e5m2_to_fp32={value[7],8'd112,23'b0};
          default: fp8_e5m2_to_fp32={value[7],8'd112,2'b10,21'b0};
        endcase
      end else if(value[6:2]==5'h1f)
        fp8_e5m2_to_fp32=value[1:0]==0?{value[7],8'hff,23'b0}:32'h7fc00000;
      else fp8_e5m2_to_fp32={value[7],value[6:2]+8'd112,value[1:0],21'b0};
    end
  endfunction

  function [31:0] fp8_e4m3fn_to_fp32;
    input [7:0] value;
    begin
      if(value[6:3]==0) begin
        case(value[2:0])
          0: fp8_e4m3fn_to_fp32={value[7],31'b0};
          1: fp8_e4m3fn_to_fp32={value[7],8'd118,23'b0};
          2: fp8_e4m3fn_to_fp32={value[7],8'd119,23'b0};
          3: fp8_e4m3fn_to_fp32={value[7],8'd119,1'b1,22'b0};
          4: fp8_e4m3fn_to_fp32={value[7],8'd120,23'b0};
          5: fp8_e4m3fn_to_fp32={value[7],8'd120,2'b01,21'b0};
          6: fp8_e4m3fn_to_fp32={value[7],8'd120,2'b10,21'b0};
          default: fp8_e4m3fn_to_fp32={value[7],8'd120,2'b11,21'b0};
        endcase
      end else if(value[6:3]==4'hf&&value[2:0]==3'b111)
        fp8_e4m3fn_to_fp32=32'h7fc00000;
      else fp8_e4m3fn_to_fp32={value[7],value[6:3]+8'd120,value[2:0],20'b0};
    end
  endfunction

  function [15:0] fp32_to_fp16;
    input [31:0] value;
    integer unbiased,rshift;
    reg [23:0] sig;
    reg [11:0] rounded;
    reg [10:0] base;
    reg guard_bit,sticky_bit;
    reg [4:0] out_exp;
    begin
      sig={1'b1,value[22:0]};
      if(value[30:23]==8'hff)
        fp32_to_fp16=value[22:0]==0?{value[31],5'h1f,10'b0}:16'h7e00;
      else if(value[30:23]==0) fp32_to_fp16={value[31],15'b0};
      else begin
        unbiased=value[30:23]-127;
        if(unbiased>15) fp32_to_fp16={value[31],5'h1f,10'b0};
        else if(unbiased>=-14) begin
          base=sig>>13; guard_bit=value[12]; sticky_bit=|value[11:0];
          rounded={1'b0,base}+(guard_bit&&(sticky_bit||base[0]));
          if(rounded[11]) begin
            out_exp=unbiased+16;
            fp32_to_fp16=out_exp==5'h1f ? {value[31],5'h1f,10'b0} :
              {value[31],out_exp,rounded[10:1]};
          end else begin out_exp=unbiased+15;
            fp32_to_fp16={value[31],out_exp,rounded[9:0]}; end
        end else if(unbiased>=-25) begin
          rshift=(-14-unbiased)+13; base=sig>>rshift;
          guard_bit=(sig>>(rshift-1))&1'b1;
          sticky_bit=sig!=((sig>>(rshift-1))<<(rshift-1));
          rounded={1'b0,base}+(guard_bit&&(sticky_bit||base[0]));
          fp32_to_fp16=rounded[10]?{value[31],5'h01,10'b0}:
            {value[31],5'h00,rounded[9:0]};
        end else fp32_to_fp16={value[31],15'b0};
      end
    end
  endfunction

  function [15:0] fp32_to_bf16;
    input [31:0] value;
    reg [16:0] rounded;
    begin
      if(value[30:23]==8'hff&&value[22:0]!=0) fp32_to_bf16=16'h7fc0;
      else begin
        rounded={1'b0,value[31:16]}+(value[15]&&((|value[14:0])||value[16]));
        fp32_to_bf16=rounded[16]?{value[31],8'hff,7'b0}:rounded[15:0];
      end
    end
  endfunction

  function [7:0] fp32_to_fp8_e5m2;
    input [31:0] value;
    integer unbiased,rshift;
    reg [23:0] sig;
    reg [3:0] rounded;
    reg [2:0] base;
    reg guard_bit,sticky_bit;
    reg [5:0] out_exp;
    begin
      sig={1'b1,value[22:0]};
      if(value[30:23]==8'hff) fp32_to_fp8_e5m2=value[22:0]!=0?8'h7e:{value[31],7'h7b};
      else if(value[30:23]==0) fp32_to_fp8_e5m2={value[31],7'b0};
      else begin
        unbiased=value[30:23]-127;
        if(unbiased>15) fp32_to_fp8_e5m2={value[31],7'h7b};
        else if(unbiased>=-14) begin
          base=sig>>21; guard_bit=value[20]; sticky_bit=|value[19:0];
          rounded={1'b0,base}+(guard_bit&&(sticky_bit||base[0])); out_exp=unbiased+15;
          if(rounded[3]) begin rounded=rounded>>1; out_exp=out_exp+1; end
          fp32_to_fp8_e5m2=out_exp>=31?{value[31],7'h7b}:
            {value[31],out_exp[4:0],rounded[1:0]};
        end else if(unbiased>=-17) begin
          rshift=7-unbiased; base=sig>>rshift; guard_bit=(sig>>(rshift-1))&1'b1;
          sticky_bit=sig!=((sig>>(rshift-1))<<(rshift-1));
          rounded={1'b0,base}+(guard_bit&&(sticky_bit||base[0]));
          fp32_to_fp8_e5m2=rounded[2]?{value[31],5'h01,2'b0}:
            {value[31],5'h00,rounded[1:0]};
        end else fp32_to_fp8_e5m2={value[31],7'b0};
      end
    end
  endfunction

  function [7:0] fp32_to_fp8_e4m3fn;
    input [31:0] value;
    integer unbiased,rshift;
    reg [23:0] sig;
    reg [4:0] rounded;
    reg [3:0] base;
    reg guard_bit,sticky_bit;
    reg [4:0] out_exp;
    begin
      sig={1'b1,value[22:0]};
      if(value[30:23]==8'hff) fp32_to_fp8_e4m3fn=value[22:0]!=0?8'h7f:{value[31],7'h7e};
      else if(value[30:23]==0) fp32_to_fp8_e4m3fn={value[31],7'b0};
      else begin
        unbiased=value[30:23]-127;
        if(unbiased>8) fp32_to_fp8_e4m3fn={value[31],7'h7e};
        else if(unbiased>=-6) begin
          base=sig>>20; guard_bit=value[19]; sticky_bit=|value[18:0];
          rounded={1'b0,base}+(guard_bit&&(sticky_bit||base[0])); out_exp=unbiased+7;
          if(rounded[4]) begin rounded=rounded>>1; out_exp=out_exp+1; end
          fp32_to_fp8_e4m3fn=(out_exp>15||(out_exp==15&&rounded[2:0]==3'b111))?
            {value[31],7'h7e}:{value[31],out_exp[3:0],rounded[2:0]};
        end else if(unbiased>=-10) begin
          rshift=14-unbiased; base=sig>>rshift; guard_bit=(sig>>(rshift-1))&1'b1;
          sticky_bit=sig!=((sig>>(rshift-1))<<(rshift-1));
          rounded={1'b0,base}+(guard_bit&&(sticky_bit||base[0]));
          fp32_to_fp8_e4m3fn=rounded[3]?{value[31],4'h1,3'b0}:
            {value[31],4'h0,rounded[2:0]};
        end else fp32_to_fp8_e4m3fn={value[31],7'b0};
      end
    end
  endfunction

  always @* begin
    load_fp32=load_value[31:0]; store_value={32'b0,store_fp32};
    case(funct3)
      3'b001: begin load_fp32=fp16_to_fp32(load_value[15:0]); store_value={48'b0,fp32_to_fp16(store_fp32)}; end
      3'b101: begin load_fp32=bf16_to_fp32(load_value[15:0]); store_value={48'b0,fp32_to_bf16(store_fp32)}; end
      3'b110: begin load_fp32=fp8_e5m2_to_fp32(load_value[7:0]); store_value={56'b0,fp32_to_fp8_e5m2(store_fp32)}; end
      3'b111: begin load_fp32=fp8_e4m3fn_to_fp32(load_value[7:0]); store_value={56'b0,fp32_to_fp8_e4m3fn(store_fp32)}; end
      default: begin end
    endcase
  end
endmodule
