`ifndef MYCPU_H
    `define MYCPU_H

    `define BR_BUS_WD       34
    `define FS_TO_DS_BUS_WD 103
    `define DS_TO_ES_BUS_WD 308
    `define ES_TO_MS_BUS_WD 221
    `define MS_TO_WS_BUS_WD 208
    `define WS_TO_RF_BUS_WD 38
    `define WS_TO_CSR_BUS   200


    `define CSR_CRMD 9'h00
    `define CSR_CRMD_PLV 1:0
    `define CSR_CRMD_IE 2
    `define CSR_CRMD_DA     3
    `define CSR_CRMD_PG     4
    `define CSR_CRMD_DATF   6:5
    `define CSR_CRMD_DATM   8:7

    `define CSR_PRMD 9'h01
    `define CSR_PRMD_PPLV 1:0
    `define CSR_PRMD_PIE 2

    `define CSR_ECFG 9'h04
    `define CSR_ECFG_LIE 12:0

    `define CSR_ESTAT 9'h05
    `define CSR_ESTAT_IS 12:0
    `define CSR_ESTAT_ECODE 21:16
    `define CSR_ESTAT_ESUBCODE 30:22
    `define CSR_ESTAT_IS10 1:0

    `define CSR_ERA 9'h06

    `define CSR_BADV 9'h07

    `define CSR_EENTRY 9'h0c
    `define CSR_EENTRY_VA 31:6

    `define CSR_SAVE0 9'h30
    `define CSR_SAVE1 9'h31
    `define CSR_SAVE2 9'h32
    `define CSR_SAVE3 9'h33

    `define CSR_TID 9'h40

    `define CSR_TCFG 9'h41
    `define CSR_TCFG_EN 0
    `define CSR_TCFG_PERIODIC 1
    `define CSR_TCFG_INITVAL 31:2

    `define CSR_TVAL 9'h42

    `define CSR_TICLR 9'h44
    `define CSR_TICLR_CLR 0

    `define CSR_TLBIDX     14'h010
    `define CSR_TLBEHI     14'h011
    `define CSR_TLBELO0    14'h012
    `define CSR_TLBELO1    14'h013
    `define CSR_ASID       14'h018
    `define CSR_TLBRENTRY  14'h088


    // TLBIDX
    `define CSR_TLBIDX_INDEX    3:0
    `define CSR_TLBIDX_PS       29:24
    `define CSR_TLBIDX_NE       31
    // TLBEHI
    `define CSR_TLBEHI_VPPN     31:13
    // TLBELO0 TLBELO1
    `define CSR_TLBELO_V        0
    `define CSR_TLBELO_D        1
    `define CSR_TLBELO_PLV      3:2
    `define CSR_TLBELO_MAT      5:4
    `define CSR_TLBELO_G        6
    `define CSR_TLBELO_PPN      31:8
    // ASID
    `define CSR_ASID_ASID       9:0
    // TLBRENTRY
    `define CSR_TLBRENTRY_PA    31:6

    `define ECODE_INT       6'h0
    `define ECODE_ADE       6'h8
    `define ECODE_ALE       6'h9
    `define ECODE_BRK       6'hc
    `define ECODE_INE       6'hd
    `define ECODE_SYS       6'hb

    `define ESUBCODE_ADEF 9'h0


    //exp19
    `define CSR_DMW0            14'h180
    `define CSR_DMW1            14'h181

    `define CSR_DMW_PLV0        0
    `define CSR_DMW_PLV3        3
    `define CSR_DMW_MAT         5:4
    `define CSR_DMW_PSEG        27:25
    `define CSR_DMW_VSEG        31:29

    `define ECODE_PIL           6'h1
    `define ECODE_PIS           6'h2
    `define ECODE_PIF           6'h3
    `define ECODE_PME           6'h4
    `define ECODE_PPI           6'h7 
    `define ECODE_TLBR          6'h3f
    `define ESUBCODE_ADEM       9'h1
    `define ECODE_IPE           6'h0E

`endif