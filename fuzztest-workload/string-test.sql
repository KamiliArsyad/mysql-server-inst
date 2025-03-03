/*
-----------------------------------------------
------ Contains simple string operations ------
-----------------------------------------------
*/
USE test1;

START TRANSACTION;
INSERT INTO tblA (txt_col, int_col)
VALUES (CONCAT('fuzz-', FLOOR(RAND()*1000)), FLOOR(RAND()*1000));
COMMIT;

START TRANSACTION;
INSERT INTO tblA (txt_col, int_col)
VALUES (CONCAT('fizz-', FLOOR(RAND()*1000)), FLOOR(RAND()*1000));
UPDATE tblA
SET txt_col = CONCAT(txt_col, '-appended')
    ORDER BY RAND()
 LIMIT 1;
COMMIT;

START TRANSACTION;
-- Delete a random row from tblA
DELETE FROM tblA
    ORDER BY RAND()
 LIMIT 1;

-- Immediately insert a new row
INSERT INTO tblA (txt_col, int_col)
VALUES (CONCAT('del-ins-', FLOOR(RAND()*1000)), FLOOR(RAND()*1000));
COMMIT;
