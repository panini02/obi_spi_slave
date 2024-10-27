// Copyright 2017 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

module spi_slave_axi_plug
#(
    parameter OBI_ADDR_WIDTH = 32,
    parameter OBI_DATA_WIDTH = 32
)
(
    // OBI MASTER
    //***************************************
    input  logic                        obi_aclk,
    input  logic                        obi_aresetn,

    // ADDRESS CHANNEL
    output logic                        obi_master_req,
    input  logic                        obi_master_gnt,
    output logic [OBI_ADDR_WIDTH-1:0]   obi_master_addr,
    output logic                        obi_master_we,
    output logic [OBI_DATA_WIDTH-1:0]   obi_master_w_data,

    // RESPONSE CHANNEL
    input  logic                        obi_master_r_valid,
    output logic                        obi_master_r_ready,  //Unsure if to be removed since not part of RI5CY and CV32E40
    input  logic [OBI_DATA_WIDTH-1:0]   obi_master_r_data,

    //SPI
    input  logic [OBI_ADDR_WIDTH-1:0]   rxtx_addr,  //I'm pretty sure rx_ready, tx_ready etc are for the SPI part and thus not altererd.
    input  logic                        rxtx_addr_valid,
    input  logic                        start_tx, 
    input  logic                        cs,
    output logic                 [31:0] tx_data,
    output logic                        tx_valid,
    input  logic                        tx_ready,
    input  logic                 [31:0] rx_data,
    input  logic                        rx_valid,         
    output logic                        rx_ready

    //NOT IMPLEMENTED OBI
    //byte enable(be) I'm unsure how it fits into the code and how it would connect to the spi part


    //OMITTED OBI(not RI5CY and CV32E40 compatible)
    //auser[]
    //wuser[]
    //aid[]
    //err
    //ruser[]
    //rid[]
    );

  logic [OBI_ADDR_WIDTH-1:0] curr_addr;
  logic [31:0]               curr_data_rx;
  logic [OBI_DATA_WIDTH-1:0] curr_data_tx;
  logic                      sample_fifo;
  logic                      sample_axidata;



  enum logic [1:0] {IDLE,OBIADDR,OBIRESP} AR_CS,AR_NS,AW_CS,AW_NS;  //Do I have to add a 4th state which defaults to the idle state to 
                                                                    //complete the FSM states?

  always_ff @(posedge obi_aclk or negedge obi_aresetn)
  begin
    if (obi_aresetn == 0)
    begin 
      AW_CS         <= IDLE;
      AR_CS         <= IDLE;
      curr_data_rx  <=  'h0;
      curr_data_tx  <=  'h0;
      curr_addr     <=  'h0;
    end
    else
    begin
      AW_CS <= AW_NS;
      AR_CS <= AR_NS;
      if (sample_fifo)
      begin
        curr_data_rx <= rx_data;
      end
      if (sample_axidata)
        curr_data_tx <= obi_master_r_data;
      if (rxtx_addr_valid)              
        curr_addr <= rxtx_addr;
    end
  end

  always_comb
  begin
    AW_NS               = IDLE;
    sample_fifo         = 1'b0; 
    rx_ready            = 1'b0;
    obi_master_req      = 1'b0;
    obi_master_we       = 1'b0;                
    obi_master_r_ready  = 1'b0;           
    case(AW_CS)
      IDLE:
      begin
        if(rx_valid)
        begin
          sample_fifo = 1'b1;
          rx_ready    = 1'b1;                 
          AW_NS       = OBIADDR;
        end
        else
        begin
          AW_NS      = IDLE;
          //obi_master_req = 0'b0;            //returning signals to 0. The AXI code didn't include returning values to their original value so I'm unsure 
          //obi_master_r_ready = 0'b0;        //whether I'm missing something or not.
        end
      end
      OBIADDR:
      begin
        obi_master_req = 1'b1;             
        obi_master_we  = 1'b1; 
        if (obi_master_gnt)
          AW_NS = OBIRESP;
        else
          AW_NS = OBIADDR;
      end
      OBIRESP:
      begin
        if (obi_master_r_valid)
        begin
          obi_master_r_ready  = 1'b1;
          AW_NS               = IDLE;
        end
        else
          AW_NS = OBIRESP;
      end
    endcase
  end

  always_comb
  begin
    AR_NS               = IDLE;
    tx_valid            = 1'b0;
    obi_master_r_ready  = 1'b0;
    obi_master_we       = 1'b0;
    sample_axidata      = 1'b0; 
    case(AR_CS)
      IDLE:
      begin
        if(start_tx && !cs)
        begin
          AR_NS      = OBIADDR;
        end
        else
        begin
          AR_NS      = IDLE;
        end
      end
      OBIADDR:
      begin
        tx_valid = 1'b1;
        if (cs)
        begin
          AR_NS = IDLE;
        end
        else
        begin
          obi_master_we       = 1'b0;
          obi_master_req      = 1'b1;   
          if(tx_ready && obi_master_gnt)  //Unsure if it is the best place to check for gnt
            begin
              AR_NS       = OBIRESP;
            end
          else              
          begin
            AR_NS      = OBIADDR;
          end
        end
      end
      OBIRESP:
      begin
        if (obi_master_r_valid)
        begin
          obi_master_r_ready = 1'b1;
          sample_axidata = 1'b1;
          AR_NS = IDLE;
        end
        else
          AR_NS = OBIRESP;
      end
    endcase
  end

  assign tx_data = curr_data_tx;
  assign obi_master_addr   =  curr_addr;
  assign obi_master_w_data    = curr_data_rx; 

endmodule
