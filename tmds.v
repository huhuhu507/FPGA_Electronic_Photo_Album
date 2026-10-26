`timescale 1ns/1ps
// TMDS encoder stages for the EG4 HDMI pipeline
module tmds_qm(
    input  wire [7:0] vd,
    output wire [8:0] qm
);
    wire [3:0] n1 = vd[0] + vd[1] + vd[2] + vd[3] + vd[4] + vd[5] + vd[6] + vd[7];
    wire enc_xnor = (n1 > 4'd4) || (n1 == 4'd4 && vd[0] == 1'b0);
    assign qm[0] = vd[0];
    assign qm[1] = enc_xnor ? ~(qm[0] ^ vd[1]) : (qm[0] ^ vd[1]);
    assign qm[2] = enc_xnor ? ~(qm[1] ^ vd[2]) : (qm[1] ^ vd[2]);
    assign qm[3] = enc_xnor ? ~(qm[2] ^ vd[3]) : (qm[2] ^ vd[3]);
    assign qm[4] = enc_xnor ? ~(qm[3] ^ vd[4]) : (qm[3] ^ vd[4]);
    assign qm[5] = enc_xnor ? ~(qm[4] ^ vd[5]) : (qm[4] ^ vd[5]);
    assign qm[6] = enc_xnor ? ~(qm[5] ^ vd[6]) : (qm[5] ^ vd[6]);
    assign qm[7] = enc_xnor ? ~(qm[6] ^ vd[7]) : (qm[6] ^ vd[7]);
    assign qm[8] = ~enc_xnor;
endmodule

module tmds_bal(
    input  wire [8:0] qm,
    input  wire [3:0] bal,
    output wire [3:0] balance,
    output wire       invert,
    output wire [3:0] inc
);
    wire [3:0] bal_sum = qm[0] + qm[1] + qm[2] + qm[3] + qm[4] + qm[5] + qm[6] + qm[7] - 4'd4;
    wire sign_eq = (bal_sum[3] == bal[3]);
    assign balance = bal_sum;
    assign invert = (bal_sum == 4'd0 || bal == 4'd0) ? ~qm[8] : sign_eq;
    assign inc = bal_sum - ({qm[8] ^ ~sign_eq} & ~(bal_sum == 4'd0 || bal == 4'd0));
endmodule
