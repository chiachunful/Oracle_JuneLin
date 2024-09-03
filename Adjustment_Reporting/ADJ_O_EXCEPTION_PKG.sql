create or replace package "ADJ_O_EXCEPTION_PKG" as
    PROCEDURE validate_data(p_collection_name IN VARCHAR2);
    FUNCTION load_data(p_collection_name IN VARCHAR2) RETURN NUMBER;
end "ADJ_O_EXCEPTION_PKG";
/

create or replace package body ADJ_O_EXCEPTION_PKG
is
    procedure validate_data (p_collection_name in varchar2)
    is 
        l_error_msg varchar2(4000);
        l_criteria varchar2(50);
        l_date date;
        l_row_count NUMBER;
        l_dummy NUMBER;
        l_dummy1 NUMBER;
        l_amount number;
        l_source varchar2(50);
        l_row_count_1 varchar2(50);
        cursor c_tasks 
        is
            select seq_id,
                   c001 as STATUS,
                   c002 as REPORT_DATE,
                   c003 as DEAL_ID,
                   c004 as INVOICE_NUM_,
                   c005 as DEAL_TYPE,
                   c006 as MOVEMENT_TYPE,
                   c007 as AMOUNT,
                   c008 as COMMENTS,
                   c009 as GL_DATE_FOR_ADJUSTMENT
          
            from apex_collections
            where collection_name = p_collection_name;
    begin
        for c in c_tasks loop
            l_error_msg := null;
       
            -- Look up DEAL_ID existence
            if c.DEAL_ID is not null then
               if c.MOVEMENT_TYPE = 'Initial movement' then 
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
                            l_error_msg := 'DEAL_ID does not meet import criteria. ';
                    end;                

                    -- Check if DEAL_ID exists in ADJUSTMENT_REPORTING for 'Initial movement'            
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
                end if;

                -- Check if a record with MOVEMENT_TYPE <> 'Initial movement' exists for the given DEAL_ID
                begin
                    select 1 into l_source
                    from (
                        select 1 as source
                        from apex_collections
                        where c003 = c.DEAL_ID
                          and collection_name = p_collection_name
                          and c006 <> 'Initial movement'
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
                                  AND SOURCE = 'Oracle'
                                union all
                                select 2 as source
                                from apex_collections
                                where c003 = c.DEAL_ID
                                  and collection_name = p_collection_name
                                  and c006 = 'Initial movement'
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

            else
                -- Handle the case where DEAL_ID is null (if needed)
                l_error_msg := 'DEAL_ID cannot be null. ';
            end if;          

            IF c.STATUS = 'Standard' THEN
                IF c.REPORT_DATE is null THEN
                    l_error_msg := l_error_msg || 'Report date cannot be null for deals with STATUS as "Standard". ';
                END IF;
            END IF;

            IF c.MOVEMENT_TYPE = '7.05 Auto Reversal' THEN
                IF c.GL_DATE_FOR_ADJUSTMENT is null THEN
                    l_error_msg := l_error_msg || 'GL_DATE_FOR_ADJUSTMENT cannot be null for MOVEMENT_TYPE as "7.05 Auto Reversal". ';
                END IF;
            END IF;            

            -- New Constraint: MOVEMENTTYPEDEALTYPECOMBINATION
            IF (c.DEAL_TYPE = 'Upfront billing / 7.05 Standard' AND c.MOVEMENT_TYPE IN ('Initial setup WHv2', '7.05 Auto Reversal'))
               OR ((c.DEAL_TYPE = '7.05 Exception' OR c.DEAL_TYPE = '7.05 Exception - Indirect') AND c.MOVEMENT_TYPE IN ('Initial setup WHv2', 'Move AR to GL', 'Move AR from GL'))
               OR (c.DEAL_TYPE = 'Warehouse v2' AND c.MOVEMENT_TYPE IN ('7.05 Auto Reversal')) THEN
                l_error_msg := l_error_msg || 'Invalid combination of DEAL_TYPE and MOVEMENT_TYPE.';
                --DBMS_OUTPUT.PUT_LINE(l_error_msg);
                --RAISE_APPLICATION_ERROR(-20001, l_error_msg);
            END IF;

            -- Check if STATUS is not one of the allowed values
            if c.STATUS is not null then
                IF c.STATUS NOT IN ('Standard', 'Change Event', 'Further Checking','Exceptional move') THEN
                    l_error_msg := l_error_msg || 'Invalid STATUS value. ';
                    -- Check for 'WIP' status and display a specific error message
                    If c.STATUS = 'WIP' THEN
                        l_error_msg := l_error_msg || 'Invalid STATUS value. ';
                    end if;
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
                IF c.DEAL_TYPE NOT IN ('7.05 Exception', '7.05 Exception - Indirect') THEN
                    l_error_msg := l_error_msg || 'Invalid DEAL_TYPE value. ';
                END IF;           
            end if;

            -- Check if MOVEMENT_TYPE is one of the valid values
            if c.MOVEMENT_TYPE is not null then
                IF c.MOVEMENT_TYPE NOT IN ('Initial movement', '7.05 Auto Reversal', 'Adjustment') THEN
                    l_error_msg := l_error_msg || 'Invalid MOVEMENT_TYPE value. ';
                END IF;            
            END IF;          

            -- Check if AMOUNT is a valid number
            if c.AMOUNT is not null then
                begin
                    l_amount := to_number(c.AMOUNT);
                exception
                    when others then 
                        l_error_msg := l_error_msg || 'Invalid AMOUNT value. ';
                end;
            else
                -- Handle the case where AMOUNT is null (if needed)
                l_error_msg := l_error_msg || 'AMOUNT cannot be null. ';
            end if;

            IF c.GL_DATE_FOR_ADJUSTMENT IS NOT NULL THEN
                BEGIN
                    l_date := CASE
                                 WHEN regexp_like(c.GL_DATE_FOR_ADJUSTMENT, '^\d{4}-\d{2}-\d{2}$') THEN
                                     TO_DATE(c.GL_DATE_FOR_ADJUSTMENT, 'YYYY-MM-DD')
                                 WHEN regexp_like(c.GL_DATE_FOR_ADJUSTMENT, '^\d{2}-[A-Za-z]{3}-\d{4}$') THEN
                                     TO_DATE(c.GL_DATE_FOR_ADJUSTMENT, 'DD-MON-YYYY')
                                 WHEN regexp_like(c.GL_DATE_FOR_ADJUSTMENT, '^\d{2}/\d{2}/\d{4}$') THEN
                                     TO_DATE(c.GL_DATE_FOR_ADJUSTMENT, 'MM/DD/YYYY')
                                 ELSE
                                     NULL  -- handle invalid format
                             END;
                    IF l_date IS NULL THEN
                        l_error_msg := l_error_msg || 'GL_DATE_FOR_ADJUSTMENT invalid format. ';
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        l_error_msg := l_error_msg || 'GL_DATE_FOR_ADJUSTMENT invalid format. ';
                END;
            END IF;

            if l_error_msg = '1' then 
                l_error_msg := null;
            end if;

            if l_error_msg is not null then
                apex_collection.update_member_attribute (
                    p_collection_name => p_collection_name,
                    p_seq =>  c.seq_id,
                    p_attr_number => 10,
                    p_attr_value => l_error_msg
                );
            end if;
        end loop;
    end validate_data;
    
    function load_data (
        p_collection_name in varchar2)
    return number
    is
        l_total_inserted_rows NUMBER := 0; -- Initialize to zero
    
    begin 
        insert into ADJUSTMENT_REPORTING(STATUS, REPORT_DATE, DEAL_ID, INVOICE_NUM_, DEAL_TYPE, MOVEMENT_TYPE,ADJUSTMENT_AMT,COMMENTS, GL_DATE_FOR_ADJUSTMENT)
            select c001 STATUS, c002 REPORT_DATE,  
                                c003 DEAL_ID, C004 INVOICE_NUM_, c005 DEAL_TYPE, c006 MOVEMENT_TYPE, c007 AMOUNT, c008 COMMENTS, c009 GL_DATE_FOR_ADJUSTMENT
            from apex_collections
            where collection_name = p_collection_name
            and c010 is null;

            l_total_inserted_rows := SQL%ROWCOUNT;
        
            return l_total_inserted_rows;
       exception
            when others then
                RAISE_APPLICATION_ERROR(-20001, 'Something went wrong. Try again later' || SQLERRM);
    end load_data;

end ADJ_O_EXCEPTION_PKG;
/