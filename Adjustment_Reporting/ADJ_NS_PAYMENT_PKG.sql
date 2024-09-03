create or replace package "ADJ_NS_PAYMENT_PKG" as
    PROCEDURE validate_data(p_collection_name IN VARCHAR2);
    FUNCTION load_data(p_collection_name IN VARCHAR2) RETURN NUMBER;
end "ADJ_NS_PAYMENT_PKG";
/

create or replace package body ADJ_NS_PAYMENT_PKG is

    procedure validate_data (p_collection_name in varchar2) is 
        l_error_msg varchar2(4000);
        l_criteria varchar2(50);  
        l_date date;
        l_row_count NUMBER;
        l_dummy NUMBER;
        l_dummy1 NUMBER;
        l_amount number;
        l_source varchar2(50);
        l_source1 varchar2(50);
        l_row_count_1 varchar2(50);
        cursor c_tasks is
            select seq_id,
                   c001 as STATUS,
                   c002 as REPORT_DATE,
                   c003 as DEAL_ID,
                   c004 as DEAL_TYPE,
                   c005 as MOVEMENT_TYPE,
                   c006 as ADJUSTMENT_AMOUNT,
                   c007 as COMMENTS,
                   c008 as OFS_PAYMENT_POSTING,
                   c009 as PAYMENT_SOURCE,
                   c010 as INVOICE_NUMBER,
                   c011 as OTHER_ADJUSTMENT,
                   c012 as ORIGINAL_INVOICE_AMOUNT,
                   c013 as PAYMENT_DISCOUNT,
                   c014 as PAYMENT_APPLIED_TO_INVOICE
            from apex_collections
            where collection_name = p_collection_name;
     

    begin
        for c in c_tasks loop
            l_error_msg := null;

            if c.DEAL_ID is not null then
                if c.MOVEMENT_TYPE = 'Initial movement' then 
                /*
                    if c.DEAL_TYPE = 'Warehouse V2' then 

                        begin
                            select 1
                            into l_criteria
                            from OFD_RECEIVABLES_MASTER orm
                            where orm.DEAL_ID = c.DEAL_ID
                                AND orm.COMPLETE_PART1 = 'Y'
                                AND orm.COMPLETE_PART2 = 'Y'
                                AND orm.COMPLETE_PART3 IS NULL
                                AND orm.BY_WHO_PART3 IS NULL
                                AND orm.DATE_PART3 IS NULL
                                AND orm.COMPLETE_PART4 IS NULL
                                AND orm.BY_WHO_PART4 IS NULL
                                AND orm.DATE_PART4 IS NULL;
                        exception
                            when no_data_found then 
                                l_error_msg := l_error_msg ||'DEAL_ID does not meet import criteria. ';
                        end;  
                */          
                    if c.DEAL_TYPE = 'Upfront' then     
                                l_error_msg := l_error_msg ||'Please use Worklist Upload for Upfront deals. ';   
                    end if;
                    -- Check if DEAL_ID exists in ADJUSTMENT_REPORTING for 'Initial movement'            
                /*
                    BEGIN
                        SELECT 1
                        INTO l_dummy1
                        FROM ADJUSTMENT_REPORTING ar
                        WHERE ar.DEAL_ID = c.DEAL_ID
                          AND ar.MOVEMENT_TYPE = 'Initial movement'
                          AND ROWNUM = 1;

                        -- If data is found, set the error message
                        l_error_msg := l_error_msg ||'Duplicate entries. ';
                     EXCEPTION
                        WHEN NO_DATA_FOUND THEN null;
                            -- No need to set an error message if no data is found
                    END;
                */

                end if;  

                if c.DEAL_TYPE != 'Warehouse V2' then 
                    -- Check if a record with MOVEMENT_TYPE <> 'Initial movement' exists for the given DEAL_ID
                    
                        begin
                            select 1 into l_source
                            from (
                                select 1 as source
                                from apex_collections
                                where c003 = c.DEAL_ID
                                  and collection_name = p_collection_name
                                  and c005 <> 'Initial movement'
                            )
                            where rownum = 1;

                            -- If such a record exists, check if a record with MOVEMENT_TYPE = 'Initial movement' exists
                            if c.MOVEMENT_TYPE <> 'Initial movement' then 

                                begin
                                    select 1 into l_source
                                    from (
                                        select 1 as source
                                        from ADJUSTMENT_REPORTING
                                        where DEAL_ID = c.DEAL_ID
                                          and MOVEMENT_TYPE = 'Initial movement'
                                          AND SOURCE = 'NetSuite'
                                        union all
                                        select 2 as source
                                        from apex_collections
                                        where c003 = c.DEAL_ID
                                          and collection_name = p_collection_name
                                          and c005 = 'Initial movement'
                                    )
                                    where rownum = 1;
                                exception
                                    when no_data_found then 
                                        l_error_msg := l_error_msg || 'DEAL_ID with Initial movement does not exist.';
                                end;
                            else null;
                            end if;
                        exception
                            when no_data_found then 
                                null;
                        end;
                END IF;
                    -- Check if there is any record with STATUS not equal to 'Standard'
                if c.MOVEMENT_TYPE <> 'Initial movement' and c.DEAL_TYPE != 'Warehouse V2' then 
                    BEGIN
                        -- Use COUNT to check if any records exist
                        SELECT COUNT(1) INTO l_dummy
                        from (
                            select 1 as source
                            from ADJUSTMENT_REPORTING
                            where DEAL_ID = c.DEAL_ID
                              and MOVEMENT_TYPE = 'Initial movement'
                              AND SOURCE = 'NetSuite'
                              AND STATUS <> 'Standard'
                            union all
                            select 2 as source
                            from apex_collections
                            where c003 = c.DEAL_ID
                              and collection_name = p_collection_name
                              and c005 = 'Initial movement'
                              AND ( c001 <> 'Standard' or c002 is null or c015 is not null)
                        )
                        WHERE ROWNUM = 1;

                        -- If any record with STATUS not equal to 'Standard' is found, raise an error
                        IF l_dummy > 0 THEN
                            l_error_msg := l_error_msg ||'Not all balance of DEAL_ID is moved. ';

                        END IF;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            -- Handle the case when no row is found (Optional)
                            DBMS_OUTPUT.PUT_LINE('No data found.');
                        WHEN OTHERS THEN
                            -- Handle other exceptions
                            DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
                    END;

                else null;
                end if;
            else
                -- Handle the case where DEAL_ID is null (if needed)
                l_error_msg := l_error_msg || 'DEAL_ID cannot be null. ';
            end if;      
        
            -- New Constraint: NSMOVEMENTTYPEDEALTYPECOMBINATION
            IF (c.DEAL_TYPE = 'Upfront' AND c.MOVEMENT_TYPE IN ('Initial setup WHv2', 'Payment JE reclass' )) THEN
                l_error_msg := l_error_msg || 'Invalid combination of DEAL_TYPE and MOVEMENT_TYPE.';
                --DBMS_OUTPUT.PUT_LINE(l_error_msg);
                --RAISE_APPLICATION_ERROR(-20001, l_error_msg);
            END IF;

            -- Check if STATUS is not one of the allowed values
            IF c.STATUS = 'Standard' THEN
                IF c.REPORT_DATE is null THEN
                    l_error_msg := l_error_msg || 'Report date cannot be null for deals with STATUS as "Standard". ';
                END IF;
            END IF;

            if c.STATUS is not null then
                IF c.STATUS NOT IN ('Standard','WIP','Change Event','Further Checking') THEN
                    l_error_msg := l_error_msg || 'Invalid STATUS value. ';
                end if;
            end if;

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
                IF c.DEAL_TYPE NOT IN ('Upfront','Warehouse V2') THEN
                    l_error_msg := l_error_msg || 'Invalid DEAL_TYPE value. ';
                END IF;           
            end if;

            -- Check if MOVEMENT_TYPE is one of the valid values
            if c.MOVEMENT_TYPE is not null then
                IF c.MOVEMENT_TYPE NOT IN ('Initial movement', 'Apply to GL', 'Move AR to GL', 'Move AR from GL', 'Payment JE reclass', 'Initial setup WHv2') THEN
                    l_error_msg := l_error_msg || 'Invalid MOVEMENT_TYPE value. ';
                END IF;            
            END IF;          

            -- Check if ADJUSTMENT_AMOUNT is a valid number
            if c.ADJUSTMENT_AMOUNT is not null then
                begin
                    l_amount := to_number(c.ADJUSTMENT_AMOUNT);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid ADJUSTMENT_AMOUNT value. ';
                end;
            else
                -- Handle the case where ADJUSTMENT_AMOUNT is null (if needed)
                l_error_msg := l_error_msg || 'ADJUSTMENT_AMOUNT cannot be null. ';
            end if;

            -- Check if OTHER_ADJUSTMENT is a valid number
            if c.OTHER_ADJUSTMENT is not null then
                begin
                    l_amount := to_number(c.OTHER_ADJUSTMENT);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid OTHER_ADJUSTMENT value. ';
                end;
            end if;

            -- Check if ORIGINAL_INVOICE_AMOUNT is a valid number
            if c.ORIGINAL_INVOICE_AMOUNT is not null then
                begin
                    l_amount := to_number(c.ORIGINAL_INVOICE_AMOUNT);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid ORIGINAL_INVOICE_AMOUNT value. ';
                end;
            end if;

            -- Check if PAYMENT_DISCOUNT is a valid number
            if c.PAYMENT_DISCOUNT is not null then
                begin
                    l_amount := to_number(c.PAYMENT_DISCOUNT);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid PAYMENT_DISCOUNT value. ';
                end;
            end if;

            -- Check if PAYMENT_APPLIED_TO_INVOICE is a valid number
            if c.PAYMENT_APPLIED_TO_INVOICE is not null then
                begin
                    l_amount := to_number(c.PAYMENT_APPLIED_TO_INVOICE);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid PAYMENT_APPLIED_TO_INVOICE value. ';
                end;
            end if;

            -- Check if OFS_PAYMENT_POSTING is 'Yes' or 'No'
            if c.OFS_PAYMENT_POSTING is not null then
                IF c.OFS_PAYMENT_POSTING NOT IN ('Yes', 'No') THEN
                    l_error_msg := l_error_msg || 'Invalid OFS_PAYMENT_POSTING value. Please provide ''Yes'' or ''No''. ';
                END IF;
            end if;

            -- Check if PAYMENT_SOURCE is one of the valid values
            if c.PAYMENT_SOURCE is not null then
                IF c.PAYMENT_SOURCE NOT IN ('Monthly pass-thru', 'INTL instruction file', 'Payment posting request', 'Email') THEN
                    l_error_msg := l_error_msg || 'Invalid PAYMENT_SOURCE value. ';
                END IF;           
            end if;

            if l_error_msg is not null then
                apex_collection.update_member_attribute (
                    p_collection_name => p_collection_name,
                    p_seq =>  c.seq_id,
                    p_attr_number => 15,
                    p_attr_value => l_error_msg
                );
            end if;
        end loop;
    end validate_data;

    function load_data (p_collection_name in varchar2) return number is
        l_total_inserted_rows NUMBER := 0;
    begin 
        insert into ADJUSTMENT_REPORTING(STATUS, REPORT_DATE, DEAL_ID, DEAL_TYPE, MOVEMENT_TYPE,ADJUSTMENT_AMT,COMMENTS,OFS_PAYMENT_POSTING,PAYMENT_SOURCE,
        INVOICE_NUM_, OTHER_ADJUSTMENT, ORIGINAL_INVOICE_AMOUNT, PAYMENT_DISCOUNT, PAYMENT_APPLIED_TO_INVOICE)
            select c001 STATUS, c002 REPORT_DATE, c003 DEAL_ID, c004 DEAL_TYPE, c005 MOVEMENT_TYPE, c006 ADJUSTMENT_AMOUNT, c007 COMMENTS, c008 OFS_PAYMENT_POSTING, c009 PAYMENT_SOURCE,
                   c010 INVOICE_NUMBER, c011 OTHER_ADJUSTMENT, c012 ORIGINAL_INVOICE_AMOUNT, c013 PAYMENT_DISCOUNT, c014 PAYMENT_APPLIED_TO_INVOICE
            from apex_collections
            where collection_name = p_collection_name
            and c015 is null;

            l_total_inserted_rows := SQL%ROWCOUNT;
        
            return l_total_inserted_rows;
       exception
            when others then
                RAISE_APPLICATION_ERROR(-20001, 'Something went wrong. Try again later' || SQLERRM);
    end load_data;

end ADJ_NS_PAYMENT_PKG;
/