USE test1;

DROP TABLE tblA;
DROP TABLE tblB;

CREATE TABLE tblA (
                      txt_col VARCHAR(100),
                      int_col INT
) ENGINE=InnoDB;

CREATE TABLE tblB (
                      txt_col VARCHAR(100),
                      int_col INT
) ENGINE=InnoDB;

DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS init_data()
BEGIN
    DECLARE i INT DEFAULT 0;
    WHILE i < 100 DO
        INSERT INTO tblA (txt_col, int_col)
        VALUES (
            CONCAT('A-', FLOOR(RAND() * 10000)),
            FLOOR(RAND() * 10000)
        );
INSERT INTO tblB (txt_col, int_col)
VALUES (
           CONCAT('B-', FLOOR(RAND() * 10000)),
           FLOOR(RAND() * 10000)
       );
SET i = i + 1;
END WHILE;
END$$
DELIMITER ;

CALL init_data();
