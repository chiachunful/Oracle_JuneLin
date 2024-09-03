create or replace package "ADJ_STATUS_UPDATE_PKG" as
    PROCEDURE validate_data(p_collection_name IN VARCHAR2);
    FUNCTION load_data(p_collection_name IN VARCHAR2) RETURN NUMBER;
end "ADJ_STATUS_UPDATE_PKG";
/

create or replace package body ADJ_STATUS_UPDATE_PKG
is
    procedure validate_data (p_collection_name in varchar2)
    is 
        l_error_msg varchar2(4000);
        l_row_count NUMBER;
        l_row_count_1 NUMBER;
        cursor c_tasks 
        is
            select seq_id,            --update listed columns
                   c001 as DEAL_ID,
                   c002 as STATUS
            from apex_collections
            where collection_name = p_collection_name;
    begin
        for c in c_tasks
        loop
            l_error_msg := null;
            
            IF c.DEAL_ID IS NULL THEN 
            l_error_msg := 'DEAL_ID cannot be null. ';
            ELSE
            -- Check if the DEAL_ID does not exist
                SELECT COUNT(*)
                INTO l_row_count
                FROM adjustment_reporting
                WHERE DEAL_ID = c.DEAL_ID;

                IF l_row_count = 0 THEN
                    l_error_msg := 'DEAL_ID does not exist in Database. ';
                END IF;
            END IF;

            IF c.STATUS IS NULL THEN 
            l_error_msg := l_error_msg || 'Status cannot be null. ';
            ELSE
                -- Check if STATUS is not one of the allowed values based on source
                SELECT COUNT(*)
                INTO l_row_count
                FROM adjustment_reporting
                WHERE DEAL_ID = c.DEAL_ID AND SOURCE = 'NetSuite' AND c.STATUS NOT IN ('WIP','Standard','Change Event', 'Further Checking');

                IF l_row_count > 0 THEN
                    l_error_msg := 'Invalid STATUS value for NetSuite deal. ';
                END IF;

                SELECT COUNT(*)
                INTO l_row_count
                FROM adjustment_reporting
                WHERE DEAL_ID = c.DEAL_ID AND SOURCE = 'Oracle' AND c.STATUS NOT IN ('WIP','Standard','Change Event', 'Further Checking', 'Exceptional move');

                IF l_row_count > 0 THEN
                    l_error_msg := 'Invalid STATUS value for Oracle deal. ';
                END IF;
            END IF;         

            -- Check if STATUS is "Standard" and report_date is null
            IF c.STATUS = 'Standard' THEN
                SELECT COUNT(*)
                INTO l_row_count_1
                FROM adjustment_reporting
                WHERE DEAL_ID = c.DEAL_ID AND report_date IS NULL;

                IF l_row_count_1 > 0 THEN
                    l_error_msg := 'Report date cannot be null for deals with STATUS as "Standard". ';
                END IF;
            END IF;

            
            if l_error_msg is not null then
                apex_collection.update_member_attribute (
                    p_collection_name => p_collection_name,
                    p_seq =>  c.seq_id,
                    p_attr_number => 3,  --Change column index for error message column
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
        FOR rec IN (SELECT * FROM apex_collections where collection_name = p_collection_name and C003 is null) LOOP

            -- Update adjustment_reporting
            UPDATE adjustment_reporting c
            SET
                c.Status = rec.C002    
            WHERE c.DEAL_ID = rec.C001;
        
            -- Increment the counter for each row updated
            l_total_inserted_rows := l_total_inserted_rows + SQL%ROWCOUNT;
        END LOOP;

        RETURN l_total_inserted_rows ;
    EXCEPTION
        WHEN others THEN
            -- Handle exceptions and provide specific error messages
            RAISE_APPLICATION_ERROR(-20001, 'Something went wrong in load_data. Try again later. ' || SQLERRM);
    END load_data;
    
end ADJ_STATUS_UPDATE_PKG;
/