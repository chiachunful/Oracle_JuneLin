create or replace package "ADJ_WORKLIST_PKG" as
    PROCEDURE validate_data(p_collection_name IN VARCHAR2);
    FUNCTION load_data(p_collection_name IN VARCHAR2) RETURN NUMBER;
end "ADJ_WORKLIST_PKG";
/

create or replace package body ADJ_worklist_pkg
is
    procedure validate_data (p_collection_name in varchar2)
    is 
        l_error_msg varchar2(4000);
        l_dummy NUMBER;
        l_assignee OFD_RECEIVABLES_MASTER.ASSIGNEE_CURRENT%TYPE;
        cursor c_tasks 
        is
            select seq_id,
                   c001 as DEAL_ID,
                   c002 as CUSTOMER_NAME,
                   c003 as FUNDING_MODEL,
                   c004 as "UCM/C@C",
                   c005 as OCE,
                   c006 as LEGALLY_REGISTERED_COUNTRY__OCE_,
                   c007 as ORACLE_INVOICES__TAX_,
                   c008 as EVENT_TYPE,
                   c009 as ORIGINAL_EVENT_DATE,
                   c010 as LAST_EVENT_DATE,
                   c011 as ORDER_NUMBER,
                   c012 as INVOICE_NUMBER,
                   c013 as OUTSTANDING_AMOUNT,
                   c014 as PAYMENT_DISCOUNT,
                   c015 as STATUS,
                   c016 as COMMENTS 
            from apex_collections
            where collection_name = 'WORKLIST_UPLOAD_COLL';
    begin
        for c in c_tasks
        loop
            l_error_msg := null;
            
            if c.DEAL_ID is null then 
                l_error_msg := 'DEAL_ID cannot be null. ';
            else
            -- Check if DEAL_ID exists in OFD_RECEIVABLES_MASTER with specified criteria
                begin
                    SELECT 1 INTO l_dummy
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
                        l_error_msg := l_error_msg || 'DEAL_ID does not meet import criteria. ';
                end;
            end if;           

        -- Validate FUNDING_MODEL
            If c.FUNDING_MODEL is null then
                l_error_msg := l_error_msg || 'FUNDING_MODEL cannot be null. ';
            elsif c.FUNDING_MODEL not in ('OFD Cloud Receivables', 'OFD Warehouse', 'Funded Admin', 'OFD Warehouse V2') then
                l_error_msg := l_error_msg || 'Invalid FUNDING_MODEL value. ';
            end if;


            -- Additional Validation if DEAL_ID is not NULL
            IF c.DEAL_ID IS NOT NULL THEN
                IF c.FUNDING_MODEL != 'OFD Warehouse V2' OR c.FUNDING_MODEL IS NULL THEN
                    BEGIN
                        -- Retrieve ASSIGNEE from OFD_RECEIVABLES_MASTER
                        BEGIN
                            SELECT ASSIGNEE_CURRENT
                            INTO l_assignee
                            FROM OFD_RECEIVABLES_MASTER
                            WHERE DEAL_ID = c.DEAL_ID
                              AND ROWNUM = 1;
                        EXCEPTION
                            WHEN NO_DATA_FOUND THEN 
                                null;
                        END;

                        -- Check for 'Initial movement' in ADJUSTMENT_REPORTING
                        BEGIN
                            SELECT 1 INTO l_dummy
                            FROM ADJUSTMENT_REPORTING ar
                            WHERE ar.DEAL_ID = c.DEAL_ID
                              AND ar.MOVEMENT_TYPE = 'Initial movement'
                              AND ROWNUM = 1;
                        EXCEPTION
                            WHEN NO_DATA_FOUND THEN 
                                NULL; -- No action needed if not found
                        END;

                        -- Check for duplicate entry in ADJUSTMENT_REPORTING
                        BEGIN
                            SELECT 1 INTO l_dummy
                            FROM ADJUSTMENT_REPORTING ar
                            WHERE ar.DEAL_ID = c.DEAL_ID
                              AND ar.ASSIGNEE = l_assignee
                              AND ar.MOVEMENT_TYPE = 'Initial movement'
                              AND ROWNUM = 1;
                            -- If found, set error message
                            l_error_msg := l_error_msg || 'Duplicate entries found. ';
                        EXCEPTION
                            WHEN NO_DATA_FOUND THEN 
                                NULL; -- No action needed if not found
                        END;

                    END;
                END IF;
            END IF;


            if l_error_msg is not null then
                apex_collection.update_member_attribute (
                    p_collection_name => p_collection_name,
                    p_seq =>  c.seq_id,
                    p_attr_number => 17,
                    p_attr_value => l_error_msg
                );
            end if;
        end loop;
    end;
    
    function load_data (
        p_collection_name in varchar2)
    return number
    is
        l_total_inserted_rows number;
    
    begin 
        INSERT INTO ADJUSTMENT_REPORTING (
            DEAL_ID,
            CUSTOMER_NAME,
            ASSIGNEE,
            FUNDING_MODEL,
            OCE,
            COUNTRY__OCE_,
            ORDER_NUMBER,
            INVOICE_NUM_,
            ORIGINAL_INVOICE_AMOUNT,
            PAYMENT_DISCOUNT,
            STATUS,
            MOVEMENT_TYPE,
            DEAL_TYPE
        )
        SELECT 
            OFD_RECEIVABLES_MASTER.DEAL_ID,
            OFD_RECEIVABLES_MASTER.CUSTOMER_LEGAL_NAME,
            OFD_RECEIVABLES_MASTER.ASSIGNEE_CURRENT,
            c003 FUNDING_MODEL,
            OFD_RECEIVABLES_MASTER.ORACLE_CONTRACT_ENTITY_OCE,
            COALESCE(OFD_RECEIVABLES_MASTER.OCE_COUNTRY, OFD_RECEIVABLES_MASTER.COUNTRY),
            c011 ORDER_NUMBER,
            c012 INVOICE_NUMBER,
            c013 OUTSTANDING_AMOUNT,
            c014 PAYMENT_DISCOUNT,
            'WIP' AS STATUS,
            CASE 
                WHEN apex_collections.c003 = 'OFD Warehouse V2' THEN 'Initial setup WHv2'
                ELSE 'Initial movement'
            END AS MOVEMENT_TYPE,
            CASE 
                WHEN apex_collections.c003 = 'OFD Warehouse V2' THEN 'Warehouse V2'
                ELSE ''
            END AS Deal_TYPE
        FROM 
            apex_collections
            JOIN OFD_RECEIVABLES_MASTER ON OFD_RECEIVABLES_MASTER.DEAL_ID = apex_collections.c001
        WHERE 
            collection_name = p_collection_name
            and apex_collections.c017 is null;

        l_total_inserted_rows := SQL%ROWCOUNT;

        RETURN l_total_inserted_rows;
    EXCEPTION
        WHEN others THEN
            -- Handle exceptions and provide specific error messages
            RAISE_APPLICATION_ERROR(-20001, 'Something went wrong in load_data. Try again later. ' || SQLERRM);
    END load_data;


end ADJ_worklist_pkg;
/