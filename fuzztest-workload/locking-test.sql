/*
----------------------------------------------------------------
----- Contains transactions involving longer lock-holding ------
----------------------------------------------------------------
*/
USE test1;

/*--- Select for update ---*/
START TRANSACTION;
SELECT id, int_col
FROM tblB
WHERE int_col IS NOT NULL
ORDER BY RAND()
    LIMIT 1
  FOR UPDATE;

-- An update that depends on the locked row
UPDATE tblB
SET int_col = int_col + 10
    ORDER BY RAND()
 LIMIT 1;
COMMIT;
/*-------------------------*/

/*--- Range query (for phantom read) ---*/
START TRANSACTION;
SELECT *
FROM tblA
WHERE int_col BETWEEN 50 AND 200;

INSERT INTO tblA (txt_col, int_col)
VALUES ('phantom-insert', 150);
COMMIT;

START TRANSACTION;
SELECT *
FROM tblB
WHERE int_col BETWEEN 50 AND 200;

INSERT INTO tblB (txt_col, int_col)
VALUES ('phantom-insert', 150);
COMMIT;
/*------------------------------------*/


/*--- Write Skew ---*/
DELIMITER $$

CREATE PROCEDURE IF NOT EXISTS InsertIfBelowThreshold()
BEGIN
    DECLARE sum_val INT;

    -- Read sum into a variable
SELECT SUM(int_col) INTO sum_val FROM tblA;

-- Conditional check
IF sum_val < 500 THEN
        INSERT INTO tblA (txt_col, int_col)
        VALUES ('aggregate-based-insert', 50);
END IF;
END $$

DELIMITER ;

-- Call the procedure
CALL InsertIfBelowThreshold();

/*------------------*/

/*--- Conditional update with subselect -----*/
START TRANSACTION;
-- Read row conditionally:
SELECT id, txt_col, int_col
FROM tblA
WHERE int_col < 100
ORDER BY RAND()
    LIMIT 1;

-- Suppose we do a second check, or rely on the old read:
-- Then do an UPDATE based on the logic:
UPDATE tblA
SET int_col = int_col + 20
WHERE int_col < 100
    ORDER BY RAND()
 LIMIT 1;
COMMIT;
/*------------------------------------------*/


/*
--- Random insert and delete ----
*/
START TRANSACTION;
-- Insert a random row into tblA
INSERT INTO tblA (txt_col, int_col)
VALUES (CONCAT('A-', FLOOR(RAND()*1000)), FLOOR(RAND()*1000));

-- Delete a random row from tblB
DELETE
FROM tblB
    ORDER BY RAND()
 LIMIT 1;

COMMIT;

START TRANSACTION;
-- Insert a random row into tblB
INSERT INTO tblB (txt_col, int_col)
VALUES (CONCAT('B-', FLOOR(RAND()*1000)), FLOOR(RAND()*1000));

-- Delete a random row from tblA
DELETE
FROM tblA
    ORDER BY RAND()
 LIMIT 1;

COMMIT;
/*---------------------------------*/
