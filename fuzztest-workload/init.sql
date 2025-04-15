USE test1;

DROP TABLE IF EXISTS tblA;
DROP TABLE IF EXISTS tblB;

CREATE TABLE tblA (
                      id INT unsigned NOT NULL AUTO_INCREMENT,
                      txt_col VARCHAR(100),
                      int_col INT,
                      PRIMARY KEY(id)
) ENGINE=InnoDB;

CREATE TABLE tblB (
                      id INT unsigned NOT NULL AUTO_INCREMENT,
                      txt_col VARCHAR(100),
                      int_col INT,
                      PRIMARY KEY(id)
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

SET GLOBAL TRANSACTION ISOLATION LEVEL REPEATABLE READ;