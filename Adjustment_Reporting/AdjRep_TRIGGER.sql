create or replace TRIGGER "AdjRep_TRIGGER" 
BEFORE INSERT or update ON ADJUSTMENT_REPORTING
FOR EACH ROW
BEGIN
    
------CREATE TIMESTAMP --
 
    IF INSERTING THEN
      :NEW.CREATED := TRUNC(SYSTIMESTAMP, 'MI');
      :NEW.CREATED_BY := APEX_APPLICATION.g_user;
      :NEW.UPDATED := NULL;
      :NEW.UPDATED_BY := NULL;
    ELSIF updating then
      :NEW.UPDATED := TRUNC(SYSTIMESTAMP, 'MI');
      :NEW.UPDATED_BY := APEX_APPLICATION.g_user;
    End IF;

----INSERT AUTO CALCULATION FOR INITIAL MOVEMENT
    IF :NEW.MOVEMENT_TYPE = 'Initial movement' AND  :NEW.SOURCE = 'NetSuite' THEN
      :NEW.ADJUSTMENT_AMT := NVL(:NEW.ORIGINAL_INVOICE_AMOUNT, 0) - NVL(:NEW.PAYMENT_DISCOUNT, 0) - NVL(:NEW.PAYMENT_APPLIED_TO_INVOICE, 0) - NVL(:NEW.OTHER_ADJUSTMENT, 0);  
    END IF;

    IF :NEW.MOVEMENT_TYPE = 'Initial movement' AND :NEW.SOURCE = 'Oracle' AND :NEW.DEAL_TYPE IN ('Upfront billing / 7.05 Standard', 'Warehouse V2') THEN
      :NEW.ADJUSTMENT_AMT := NVL(:NEW.ORIGINAL_INVOICE_AMOUNT, 0) - NVL(:NEW.PAYMENT_DISCOUNT, 0) - NVL(:NEW.PAYMENT_APPLIED_TO_INVOICE, 0) - NVL(:NEW.OTHER_ADJUSTMENT, 0);    
    END IF;

----LOCK UP COLUMNS - ORIGINAL INVOICE AMOUNT, PAYMENT DISCOUNT, OTHER ADJUSTMENT, PAYMENT APPLIED TO INVOICE BASED ON SOURCE/MOVEMENT TYPE----
    IF :NEW.SOURCE = 'Oracle' THEN
      IF :NEW.MOVEMENT_TYPE IN ('7.05 Auto Reversal','Move AR to GL', 'Move AR from GL', 'Adjustment', 'Initial setup WHv2') THEN
        :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
        :NEW.ORIGINAL_INVOICE_AMOUNT := Null;
        :NEW.PAYMENT_DISCOUNT := Null;
        :NEW.OTHER_ADJUSTMENT := Null;
      ELSIF :NEW.MOVEMENT_TYPE = 'Payment application' THEN
        :NEW.ORIGINAL_INVOICE_AMOUNT := Null;
        :NEW.PAYMENT_DISCOUNT := Null;
        :NEW.OTHER_ADJUSTMENT := Null;
      ELSIF :NEW.MOVEMENT_TYPE = 'Initial movement' AND (:NEW.DEAL_TYPE = '7.05 Exception' OR :NEW.DEAL_TYPE = '7.05 Exception - Indirect') THEN
        :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
        :NEW.ORIGINAL_INVOICE_AMOUNT := Null;
        :NEW.PAYMENT_DISCOUNT := Null;
        :NEW.OTHER_ADJUSTMENT := Null;
      END IF;
    ELSIF :NEW.SOURCE = 'NetSuite' THEN
      IF :NEW.MOVEMENT_TYPE IN ('Move AR to GL', 'Move AR from GL', 'Payment JE reclass', 'Initial setup WHv2') THEN
        :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
        :NEW.ORIGINAL_INVOICE_AMOUNT := Null;
        :NEW.PAYMENT_DISCOUNT := Null;
        :NEW.OTHER_ADJUSTMENT := Null;
      ELSIF :NEW.MOVEMENT_TYPE = 'Apply to GL' THEN
        :NEW.ORIGINAL_INVOICE_AMOUNT := Null;
        :NEW.PAYMENT_DISCOUNT := Null;
        :NEW.OTHER_ADJUSTMENT := Null;
      END IF;    
    END IF;
        
-----NetSuite Conditions FOR ACCT MOVEMENT
    IF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 AND :NEW.DEAL_TYPE = 'Upfront' THEN
     :NEW.ADJUSTMENT_TYPE := 'CM';
     :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
     :NEW.OFD_CLD_14745 := :NEW.ADJUSTMENT_AMT;
     :NEW.OFD_WH_14746 := Null;
     :NEW.OFD_WHV2_19846 := Null;
     :NEW.OFD_WHV2_19848 := Null;
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Upfront' THEN
     :NEW.ADJUSTMENT_TYPE := 'CM';
     :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
     :NEW.OFD_CLD_14745 := Null;
     :NEW.OFD_WH_14746 := :NEW.ADJUSTMENT_AMT;
     :NEW.OFD_WHV2_19846 := Null;
     :NEW.OFD_WHV2_19848 := Null;
    ---condition for Warehouse V2
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN
     :NEW.ADJUSTMENT_TYPE := 'CM';
     :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
     :NEW.OFD_CLD_14745 := Null;
     :NEW.OFD_WH_14746 := Null;
     :NEW.OFD_WHV2_19846 := Null;
     :NEW.OFD_WHV2_19848 := :NEW.ADJUSTMENT_AMT;

    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Initial setup WHv2' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN
     :NEW.ADJUSTMENT_TYPE := 'JE';
     :NEW.TRADE_AR := Null;
     :NEW.OFD_CLD_14745 := Null;
     :NEW.OFD_WH_14746 := Null;
     :NEW.OFD_WHV2_19846 := :NEW.ADJUSTMENT_AMT;
     :NEW.OFD_WHV2_19848 := - :NEW.ADJUSTMENT_AMT;

    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Payment JE reclass' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN
     :NEW.ADJUSTMENT_TYPE := 'JE';
     :NEW.TRADE_AR := Null;
     :NEW.OFD_CLD_14745 := Null;
     :NEW.OFD_WH_14746 := Null;
     :NEW.OFD_WHV2_19846 := - :NEW.ADJUSTMENT_AMT;
     :NEW.OFD_WHV2_19848 := :NEW.ADJUSTMENT_AMT;
    ------
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Apply to GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 AND :NEW.DEAL_TYPE = 'Upfront' THEN
      :NEW.ADJUSTMENT_TYPE := 'Application';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := :NEW.ADJUSTMENT_AMT;
      :NEW.ORIGINAL_INVOICE_AMOUNT := Null;
      :NEW.PAYMENT_DISCOUNT := Null;
      :NEW.OTHER_ADJUSTMENT := Null;
      :NEW.TRADE_AR := Null;
      :NEW.OFD_CLD_14745 := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_WH_14746 := Null;
      :NEW.OFD_WHV2_19846 := Null;
      :NEW.OFD_WHV2_19848 := Null;
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Apply to GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Upfront' THEN
      :NEW.ADJUSTMENT_TYPE := 'Application';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := :NEW.ADJUSTMENT_AMT;
      :NEW.ORIGINAL_INVOICE_AMOUNT:= Null;
      :NEW.PAYMENT_DISCOUNT:= Null;
      :NEW.OTHER_ADJUSTMENT:= Null;
      :NEW.TRADE_AR := Null;
      :NEW.OFD_CLD_14745 := Null;
      :NEW.OFD_WH_14746 := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_WHV2_19846 := Null;
      :NEW.OFD_WHV2_19848 := Null;
    
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Apply to GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN
      :NEW.ADJUSTMENT_TYPE := 'Application';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := :NEW.ADJUSTMENT_AMT;
      :NEW.ORIGINAL_INVOICE_AMOUNT:= Null;
      :NEW.PAYMENT_DISCOUNT:= Null;
      :NEW.OTHER_ADJUSTMENT:= Null;
      :NEW.TRADE_AR := Null;
      :NEW.OFD_CLD_14745 := Null;
      :NEW.OFD_WH_14746 := Null;
      :NEW.OFD_WHV2_19846 := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_WHV2_19848 := Null;

    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Move AR to GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 AND :NEW.DEAL_TYPE = 'Upfront' THEN
      :NEW.ADJUSTMENT_TYPE := 'CM';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
      :NEW.ORIGINAL_INVOICE_AMOUNT:= Null;
      :NEW.PAYMENT_DISCOUNT:= Null;
      :NEW.OTHER_ADJUSTMENT:= Null;
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_CLD_14745 := :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_WH_14746 := Null;
      :NEW.OFD_WHV2_19846 := Null;
      :NEW.OFD_WHV2_19848 := Null;
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Move AR to GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Upfront' THEN
      :NEW.ADJUSTMENT_TYPE := 'CM';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
      :NEW.ORIGINAL_INVOICE_AMOUNT:= Null;
      :NEW.PAYMENT_DISCOUNT:= Null;
      :NEW.OTHER_ADJUSTMENT:= Null;
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_CLD_14745 := Null;
      :NEW.OFD_WH_14746 := :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_WHV2_19846 := Null;
      :NEW.OFD_WHV2_19848 := Null;
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Move AR to GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN
      :NEW.ADJUSTMENT_TYPE := 'CM';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
      :NEW.ORIGINAL_INVOICE_AMOUNT:= Null;
      :NEW.PAYMENT_DISCOUNT:= Null;
      :NEW.OTHER_ADJUSTMENT:= Null;
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_CLD_14745 := Null;
      :NEW.OFD_WH_14746 := Null;
      :NEW.OFD_WHV2_19846 := Null;
      :NEW.OFD_WHV2_19848 := :NEW.ADJUSTMENT_AMT;
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Move AR from GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 AND :NEW.DEAL_TYPE = 'Upfront' THEN
      :NEW.ADJUSTMENT_TYPE := 'Manual invoice';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
      :NEW.ORIGINAL_INVOICE_AMOUNT:= Null;
      :NEW.PAYMENT_DISCOUNT:= Null;
      :NEW.OTHER_ADJUSTMENT:= Null;
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_CLD_14745 := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_WH_14746 := Null;
      :NEW.OFD_WHV2_19846 := Null;
      :NEW.OFD_WHV2_19848 := Null;
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Move AR from GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Upfront' THEN
      :NEW.ADJUSTMENT_TYPE := 'Manual invoice';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
      :NEW.ORIGINAL_INVOICE_AMOUNT:= Null;
      :NEW.PAYMENT_DISCOUNT:= Null;
      :NEW.OTHER_ADJUSTMENT:= Null;
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_CLD_14745 := Null;
      :NEW.OFD_WH_14746 := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_WHV2_19846 := Null;
      :NEW.OFD_WHV2_19848 := Null;
    ELSIF :NEW.SOURCE = 'NetSuite' AND :NEW.MOVEMENT_TYPE = 'Move AR from GL' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN
      :NEW.ADJUSTMENT_TYPE := 'Manual invoice';
      :NEW.PAYMENT_APPLIED_TO_INVOICE := Null;
      :NEW.ORIGINAL_INVOICE_AMOUNT:= Null;
      :NEW.PAYMENT_DISCOUNT:= Null;
      :NEW.OTHER_ADJUSTMENT:= Null;
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_CLD_14745 := Null;
      :NEW.OFD_WH_14746 := Null;
      :NEW.OFD_WHV2_19846 := - :NEW.ADJUSTMENT_AMT;
      :NEW.OFD_WHV2_19848 := Null;
    END IF;

-----Oracle Conditions FOR ACCT MOVEMENT
--INITIAL MOVEMENT
    IF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND :NEW.DEAL_TYPE = 'Upfront billing / 7.05 Standard' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND :NEW.DEAL_TYPE = 'Upfront billing / 7.05 Standard' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;

    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND :NEW.DEAL_TYPE = '7.05 Exception' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'Rev Adj';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := - :NEW.ADJUSTMENT_AMT;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND :NEW.DEAL_TYPE = '7.05 Exception' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'Rev Adj';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := - :NEW.ADJUSTMENT_AMT;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;

    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND :NEW.DEAL_TYPE = '7.05 Exception - Indirect' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'Rev Adj';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := - :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_CLD_120604" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND :NEW.DEAL_TYPE = '7.05 Exception - Indirect' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'Rev Adj';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := - :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;  
    
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Initial movement' AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN 
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := :NEW.ADJUSTMENT_AMT; 
    
    --INITIAL SETUP WHV2

    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Initial setup WHv2' AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN 
      :NEW.ADJUSTMENT_TYPE := 'JE';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM297" := - :NEW.ADJUSTMENT_AMT;   
    
    --AUTO REVERSAL
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = '7.05 Auto Reversal' AND :NEW.DEAL_TYPE = '7.05 Exception' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'Rev Adj';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := :NEW.ADJUSTMENT_AMT;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := -:NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF  :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = '7.05 Auto Reversal' AND :NEW.DEAL_TYPE = '7.05 Exception' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'Rev Adj';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := :NEW.ADJUSTMENT_AMT;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := -:NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;

    ELSIF  :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = '7.05 Auto Reversal' AND :NEW.DEAL_TYPE = '7.05 Exception - Indirect' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'Rev Adj';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_CLD_120604" := -:NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF  :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = '7.05 Auto Reversal' AND :NEW.DEAL_TYPE = '7.05 Exception - Indirect' AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 THEN 
      :NEW.ADJUSTMENT_TYPE := 'Rev Adj';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := -:NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;  
    
    -- Payment Application
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Payment application' AND :NEW.DEAL_TYPE = 'Upfront billing / 7.05 Standard' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := :NEW.ADJUSTMENT_AMT;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := - :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Payment application' AND :NEW.DEAL_TYPE = 'Upfront billing / 7.05 Standard'  AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := :NEW.ADJUSTMENT_AMT;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := - :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;

    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Payment application' AND :NEW.DEAL_TYPE = '7.05 Exception' THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := :NEW.ADJUSTMENT_AMT;
      :NEW.ADJUSTMENT_TYPE := 'Application';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF  :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Payment application' AND :NEW.DEAL_TYPE = '7.05 Exception - Indirect' THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := :NEW.ADJUSTMENT_AMT;
      :NEW.ADJUSTMENT_TYPE := 'Application';
      :NEW.TRADE_AR := null;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;

    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Payment application' AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := :NEW.ADJUSTMENT_AMT;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := - :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM297" := null;
    
    -- Move AR to GL
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Move AR to GL' AND :NEW.DEAL_TYPE = 'Upfront billing / 7.05 Standard' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := null;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Move AR to GL' AND :NEW.DEAL_TYPE = 'Upfront billing / 7.05 Standard'  AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := null;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;

    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Move AR to GL' AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := null;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := - :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := :NEW.ADJUSTMENT_AMT;

    -- Move AR from GL
    ELSIF  :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Move AR from GL' AND :NEW.DEAL_TYPE = 'Upfront billing / 7.05 Standard' AND INSTR(UPPER(:NEW.ASSIGNEE), 'CLOUD') > 0 THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := null;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := - :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;
    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Move AR from GL' AND :NEW.DEAL_TYPE = 'Upfront billing / 7.05 Standard'  AND INSTR(UPPER(:NEW.ASSIGNEE), 'WAREHOUSE') > 0 THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := null;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := - :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM232" := null;
      :NEW."OFD_WHV2_XM297" := null;

    ELSIF :NEW.SOURCE = 'Oracle' AND :NEW.MOVEMENT_TYPE = 'Move AR from GL' AND :NEW.DEAL_TYPE = 'Warehouse V2' THEN 
      :NEW.PAYMENT_APPLIED_TO_INVOICE := null;
      :NEW.ADJUSTMENT_TYPE := 'AR Adjustment';
      :NEW.TRADE_AR := :NEW.ADJUSTMENT_AMT;
      :NEW.UNBILLED := null;
      :NEW."AR_AP_NETTING" := null;
      :NEW."OFD_CLD_120604" := null;
      :NEW."OFD_WH_120804" := null;
      :NEW."OFD_WHV2_XM232" := - :NEW.ADJUSTMENT_AMT;
      :NEW."OFD_WHV2_XM297" := null;
        
    END IF;

 END;
/