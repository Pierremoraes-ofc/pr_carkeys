-- ============================================================
--   pr_carkeys — install/pr_carkeys.sql
--   Execute este arquivo caso o Auto SQL não funcione.
-- ============================================================

CREATE TABLE IF NOT EXISTS `pr_carkeys` (
    `id`         INT          NOT NULL AUTO_INCREMENT,
    `barcode`    VARCHAR(20)  NOT NULL UNIQUE               COMMENT 'Código de barras único da chave (metadata)',
    `citizenid`  VARCHAR(50)  NOT NULL                      COMMENT 'CitizenID do dono da chave',
    `plate`      VARCHAR(15)  NOT NULL                      COMMENT 'Placa do veículo',
    `key_type`   VARCHAR(20)  NOT NULL DEFAULT 'permanent'  COMMENT 'permanent | temporary | single_use',
    `sound`      VARCHAR(50)  NOT NULL DEFAULT 'lock'       COMMENT 'Nome do som configurado',
    `motor`      TINYINT(1)   NOT NULL DEFAULT 0            COMMENT '1 = liga motor ao destrancar',
    `level`      VARCHAR(20)  NOT NULL DEFAULT 'original'   COMMENT 'original | copy',
    `distance`   FLOAT        NOT NULL DEFAULT 5.0          COMMENT 'Distância do sinal (metros)',
    `expires_at` BIGINT       NULL DEFAULT NULL             COMMENT 'Timestamp UNIX de expiração (apenas temporary)',
    `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_barcode`   (`barcode`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_plate`     (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Configurações individuais das chaves de veículo';
