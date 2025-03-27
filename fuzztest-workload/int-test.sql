/*
-----------------------------------------------
----- Contains simple integer operations ------
-----------------------------------------------
*/
USE test1;

/* --- Increment --- */
START TRANSACTION;
UPDATE tblA
SET int_col = int_col + 1
    ORDER BY RAND()
 LIMIT 1;
COMMIT;

START TRANSACTION;
UPDATE tblB
SET int_col = int_col + 1
    ORDER BY RAND()
 LIMIT 1;
COMMIT;

/*--- Simple attempt for write skew: ---*/

START TRANSACTION;
SELECT id, int_col INTO @a_val
FROM tblA
ORDER BY RAND()
    LIMIT 1;

UPDATE tblB
SET int_col = int_col + @a_val
    ORDER BY RAND()
 LIMIT 1;
COMMIT;

START TRANSACTION;
SELECT id, int_col INTO @b_val
FROM tblB
ORDER BY RAND()
    LIMIT 1;

UPDATE tblA
SET int_col = int_col + @b_val
    ORDER BY RAND()
 LIMIT 1;
COMMIT;
