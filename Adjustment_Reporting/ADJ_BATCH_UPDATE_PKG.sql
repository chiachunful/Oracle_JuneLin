create or replace package "ADJ_BATCH_UPDATE_PKG" as
    PROCEDURE validate_data(p_collection_name IN VARCHAR2);
    FUNCTION load_data(p_collection_name IN VARCHAR2) RETURN NUMBER;
end "ADJ_BATCH_UPDATE_PKG";
/

create or replace package body ADJ_BATCH_UPDATE_PKG
is
    procedure validate_data (p_collection_name in varchar2)
    is 
        l_error_msg varchar2(4000);
        l_row_count NUMBER;
        l_date date;
        l_amount1 number;
        l_amount2 number;  
        l_amount3 number;  
        l_amount4 number;  

        cursor c_tasks 
        is
            select seq_id,
                   c001 as DEAL_TYPE,
                   c002 as REPORT_DATE,
                   c003 as MOVEMENT_TYPE,
                   c004 as COUNTRY__OCE_,
                   c005 as CUSTOMER_NAME,
                   c006 as DEAL_ID,
                   c007 as ORDER_NUMBER,
                   c008 as INVOICE_NUM,
                   c009 as ADJUSTMENT_AMT,
                   c010 as OTHER_ADJUSTMENT,
                   c011 as ORIGINAL_INVOICE_AMOUNT,
                   c012 as PAYMENT_DISCOUNT,
                   c013 as PAYMENT_APPLIED_TO_INVOICE,
                   c014 as COMMENTS,
                   c015 as ASSIGNEE
            from apex_collections
            where collection_name = p_collection_name;
    begin
        for c in c_tasks
        loop
            l_error_msg := null;
            
            IF c.DEAL_ID IS NULL THEN 
            l_error_msg := 'DEAL_ID cannot be null. ';
            ELSE
            -- Check if the combination of DEAL_ID and INVOICE_NUM does not exist
                SELECT COUNT(*)
                INTO l_row_count
                FROM adjustment_reporting
                WHERE DEAL_ID = c.DEAL_ID AND INVOICE_NUM_ = c.INVOICE_NUM and MOVEMENT_TYPE = c.MOVEMENT_TYPE;

                IF l_row_count = 0 THEN
                    l_error_msg := 'Record does not exist in Database. ';
                END IF;
            END IF;
            
            IF c.REPORT_DATE IS NOT NULL THEN
                BEGIN
                    l_date := CASE
                                 WHEN regexp_like(c.REPORT_DATE, '^\d{4}-\d{2}-\d{2}$') THEN
                                     TO_DATE(c.REPORT_DATE, 'YYYY-MM-DD')
                                 WHEN regexp_like(c.REPORT_DATE, '^\d{2}-[A-Za-z]{3}-\d{4}$') THEN
                                     TO_DATE(c.REPORT_DATE, 'DD-MON-YYYY')
                                 WHEN regexp_like(c.REPORT_DATE, '^\d{2}/\d{2}/\d{4}$') THEN
                                     TO_DATE(c.REPORT_DATE, 'MM/DD/YYYY')
                                 ELSE
                                     NULL  -- handle invalid format
                             END;
                    IF l_date IS NULL THEN
                        l_error_msg := l_error_msg || 'Report date invalid format. ';
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        l_error_msg := l_error_msg || 'Report date invalid format. ';
                END;
            END IF;
           
            -- Check if DEAL_TYPE is one of the valid values
            if c.DEAL_TYPE is not null then
                IF c.DEAL_TYPE NOT IN ('Upfront billing / 7.05 Standard',  '7.05 Exception', '7.05 Exception - Indirect','Warehouse V2' ,'Upfront') THEN
                    l_error_msg := l_error_msg || 'Invalid DEAL_TYPE value. ';
                END IF;           
            end if;

            -- Check if MOVEMENT_TYPE is one of the valid values
            if c.MOVEMENT_TYPE is not null then
                IF c.MOVEMENT_TYPE NOT IN ('Initial movement') THEN
                    l_error_msg := l_error_msg || 'Invalid MOVEMENT_TYPE value; it should only be "Initial movement" ';
                END IF;            
            END IF;          

            -- Check if Other Adjustment is a valid number
            if c.OTHER_ADJUSTMENT is not null then
                begin
                    l_amount1 := to_number(c.OTHER_ADJUSTMENT);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid OTHER_ADJUSTMENT value. ';
                end;
            end if;

            -- Check if ORIGINAL_INVOICE_AMOUNT is a valid number
            if c.ORIGINAL_INVOICE_AMOUNT is not null then
                begin
                    l_amount2 := to_number(c.ORIGINAL_INVOICE_AMOUNT);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid ORIGINAL_INVOICE_AMOUNT value. ';
                end;
            end if;            

            -- Check if PAYMENT_DISCOUNT is a valid number
            if c.PAYMENT_DISCOUNT is not null then
                begin
                    l_amount3 := to_number(c.PAYMENT_DISCOUNT);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid PAYMENT_DISCOUNT value. ';
                end;
            end if;  

            -- Check if PAYMENT_APPLIED_TO_INVOICE is a valid number
            if c.PAYMENT_APPLIED_TO_INVOICE is not null then
                begin
                    l_amount4 := to_number(c.PAYMENT_APPLIED_TO_INVOICE);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid PAYMENT_APPLIED_TO_INVOICE value. ';
                end;
            end if;  
                        
            if l_error_msg is not null then
                apex_collection.update_member_attribute (
                    p_collection_name => p_collection_name,
                    p_seq =>  c.seq_id,
                    p_attr_number => 16,
                    p_attr_value => l_error_msg
                );
            end if;
        end loop;
    end;
    
    function load_data (
        p_collection_name in varchar2)
    return number
    is
        l_total_inserted_rows NUMBER := 0; -- Initialize to zero
    
    begin 
        FOR rec IN (SELECT * FROM apex_collections where collection_name = p_collection_name) LOOP

            -- Update adjustment_reporting
            UPDATE adjustment_reporting c
            SET
                c.DEAL_TYPE = COALESCE(rec.C001, c.DEAL_TYPE),
                c.report_date = NVL(rec.c002, c.report_date),
                c.other_adjustment = TO_NUMBER(COALESCE(rec.C010, TO_CHAR(c.other_adjustment))),
                c.original_invoice_amount = TO_NUMBER(COALESCE(rec.C011, TO_CHAR(c.original_invoice_amount))),
                c.payment_discount = TO_NUMBER(COALESCE(rec.C012, TO_CHAR(c.payment_discount))),
                c.payment_applied_to_invoice = TO_NUMBER(COALESCE(rec.C013,TO_CHAR(c.payment_applied_to_invoice))),
                c.comments = COALESCE(rec.C014, c.comments)
            WHERE c.DEAL_ID = rec.C006 and c.INVOICE_NUM_ = rec.C008 and  c.MOVEMENT_TYPE = rec.C003 and rec.c016 is null;
        
            -- Increment the counter for each row updated
            l_total_inserted_rows := l_total_inserted_rows + SQL%ROWCOUNT;
        END LOOP;

        RETURN l_total_inserted_rows ;
    EXCEPTION
        WHEN others THEN
            -- Handle exceptions and provide specific error messages
            RAISE_APPLICATION_ERROR(-20001, 'Something went wrong in load_data. Try again later. ' || SQLERRM);
    END load_data;
    

end ADJ_BATCH_UPDATE_PKG;
/