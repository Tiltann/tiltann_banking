-- Database schema. Created on start by server/database/migrate.lua: missing
-- tables are installed, columns added in later versions are added to old
-- tables. There is nothing to import by hand.
--
-- All statements are `CREATE TABLE IF NOT EXISTS`, so this is safe to run
-- again and again.

TbSchema = [==[
-- tiltann_banking database schema
--
-- All statements are `CREATE TABLE IF NOT EXISTS`, so this file is safe to
-- run repeatedly (server/database/migrate.lua does exactly that on every
-- resource start). Money columns are whole units of the server currency
-- stored as INT, no floats anywhere.

-- --------------------------------------------------------------------------
-- tb_accounts: every balance-holding entity in one table (pefcl-style).
--   personal : a player's own account. Several per player; exactly one has
--              is_default = 1, that one mirrors ESX's own bank balance and
--              is what the ATM/loans/tax default to.
--   savings  : a player's interest-earning account. No card, never bridged.
--   society  : a business. job_name set = linked to an ESX job (auto access
--              by grade, bridged to esx_addonaccount/esx_society); NULL = a
--              standalone business reachable only via tb_account_members.
-- Soft-deleted rows (deleted_at set) are kept for the audit trail and are
-- never returned by any lookup.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_accounts` (
	`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`type` ENUM('personal', 'savings', 'society') NOT NULL,
	`owner_identifier` VARCHAR(64) DEFAULT NULL,
	`job_name` VARCHAR(50) DEFAULT NULL,
	`number` VARCHAR(20) NOT NULL,
	`name` VARCHAR(50) NOT NULL,
	`balance` INT NOT NULL DEFAULT 0,
	`is_default` TINYINT(1) NOT NULL DEFAULT 0,
	`is_treasury` TINYINT(1) NOT NULL DEFAULT 0,
	`interest_rate` DECIMAL(6, 3) DEFAULT NULL,
	`last_interest_at` TIMESTAMP NULL DEFAULT NULL,
	`locked_until` TIMESTAMP NULL DEFAULT NULL,
	`history_cleared_at` TIMESTAMP NULL DEFAULT NULL,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	`updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	`deleted_at` TIMESTAMP NULL DEFAULT NULL,
	PRIMARY KEY (`id`),
	UNIQUE KEY `tb_accounts_number_unique` (`number`),
	KEY `tb_accounts_owner_idx` (`owner_identifier`, `type`, `deleted_at`),
	KEY `tb_accounts_job_idx` (`job_name`, `deleted_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_account_members: explicit per-player access to a business, independent
-- of ESX job. Role decides capabilities via Config.Society.RoleCapabilities.
-- card_daily_limit caps that member's company-card ATM withdrawals per day
-- (NULL = Config.Cards.DefaultStaffDailyLimit).
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_account_members` (
	`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`account_id` INT UNSIGNED NOT NULL,
	`identifier` VARCHAR(64) NOT NULL,
	`role` ENUM('owner', 'admin', 'contributor') NOT NULL DEFAULT 'contributor',
	-- RP name captured when the member was added, so the staff list stays
	-- readable after they log off (identifiers mean nothing to a reader).
	`display_name` VARCHAR(100) DEFAULT NULL,
	`card_daily_limit` INT DEFAULT NULL,
	`added_by` VARCHAR(64) DEFAULT NULL,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `tb_account_members_unique` (`account_id`, `identifier`),
	KEY `tb_account_members_identifier_idx` (`identifier`),
	CONSTRAINT `tb_account_members_account_fk` FOREIGN KEY (`account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_society_grade_roles: per-job-grade role overrides for job-linked
-- businesses. A grade with no row gets Config.Society.DefaultGradeRole; the
-- job's highest grade is always 'owner' when HighestGradeIsOwner.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_society_grade_roles` (
	`job_name` VARCHAR(50) NOT NULL,
	`grade` INT UNSIGNED NOT NULL,
	`role` ENUM('owner', 'admin', 'contributor') NOT NULL,
	PRIMARY KEY (`job_name`, `grade`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_transactions: universal audit log for every money movement. from/to are
-- both nullable so a deposit (cash -> account) only sets to_account_id, a
-- withdrawal only from_account_id, and a transfer sets both.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_transactions` (
	`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	`from_account_id` INT UNSIGNED DEFAULT NULL,
	`to_account_id` INT UNSIGNED DEFAULT NULL,
	`type` ENUM(
		'deposit', 'withdraw', 'transfer', 'tax', 'interest', 'standing_order',
		'loan_disbursement', 'loan_repayment', 'invoice_payment', 'account_fee',
		'admin_adjustment', 'sync_correction'
	) NOT NULL,
	`amount` INT NOT NULL,
	-- Balance of the account most relevant to this row (to_account_id if set,
	-- else from_account_id) immediately after the mutation.
	`balance_after` INT NOT NULL,
	`actor_identifier` VARCHAR(64) DEFAULT NULL,
	`note` VARCHAR(255) DEFAULT NULL,
	`metadata` JSON DEFAULT NULL,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `tb_transactions_from_idx` (`from_account_id`, `created_at`),
	KEY `tb_transactions_to_idx` (`to_account_id`, `created_at`),
	KEY `tb_transactions_type_idx` (`type`, `created_at`),
	CONSTRAINT `tb_transactions_from_fk` FOREIGN KEY (`from_account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE SET NULL,
	CONSTRAINT `tb_transactions_to_fk` FOREIGN KEY (`to_account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_sync_log: bookkeeping for server/bridge/external_bridge.lua so its
-- inbound poll can tell "this changed because WE pushed it" apart from
-- "something else changed it", see that file's header comment.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_sync_log` (
	`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	`account_id` INT UNSIGNED NOT NULL,
	`target` VARCHAR(40) NOT NULL,
	`direction` ENUM('outbound', 'inbound') NOT NULL,
	`resulting_balance` INT NOT NULL,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `tb_sync_log_account_idx` (`account_id`, `target`, `created_at`),
	CONSTRAINT `tb_sync_log_account_fk` FOREIGN KEY (`account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_cards: one physical ox_inventory card per (holder, account). The PIN is
-- NEVER in item metadata, only its salted hash lives here. is_locked is the
-- holder's own reversible freeze; status = 'blocked' is the PIN-lockout.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_cards` (
	`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`account_id` INT UNSIGNED NOT NULL,
	`holder_identifier` VARCHAR(64) NOT NULL,
	`number` CHAR(16) NOT NULL,
	`pin_hash` CHAR(64) DEFAULT NULL,
	`pin_salt` CHAR(32) DEFAULT NULL,
	`inventory_serial` VARCHAR(64) DEFAULT NULL,
	`status` ENUM('active', 'blocked', 'lost') NOT NULL DEFAULT 'active',
	`is_locked` TINYINT(1) NOT NULL DEFAULT 0,
	`failed_pin_attempts` TINYINT UNSIGNED NOT NULL DEFAULT 0,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	`updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `tb_cards_number_unique` (`number`),
	KEY `tb_cards_holder_idx` (`holder_identifier`, `status`),
	KEY `tb_cards_account_holder_idx` (`account_id`, `holder_identifier`, `status`),
	CONSTRAINT `tb_cards_account_fk` FOREIGN KEY (`account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_standing_orders: recurring transfers. Runs from a specific account the
-- creator controls to any account number.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_standing_orders` (
	`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`from_account_id` INT UNSIGNED NOT NULL,
	`to_account_number` VARCHAR(20) NOT NULL,
	`amount` INT NOT NULL,
	`interval_seconds` INT UNSIGNED NOT NULL,
	`next_run_at` TIMESTAMP NOT NULL,
	`note` VARCHAR(100) DEFAULT NULL,
	`created_by` VARCHAR(64) DEFAULT NULL,
	`active` TINYINT(1) NOT NULL DEFAULT 1,
	`failed_runs` TINYINT UNSIGNED NOT NULL DEFAULT 0,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `tb_standing_orders_due_idx` (`active`, `next_run_at`),
	KEY `tb_standing_orders_from_idx` (`from_account_id`),
	CONSTRAINT `tb_standing_orders_from_fk` FOREIGN KEY (`from_account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_loans / tb_loan_payments (loans attach to the borrower's default account)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_loans` (
	`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`account_id` INT UNSIGNED NOT NULL,
	`borrower_identifier` VARCHAR(64) NOT NULL,
	`principal` INT NOT NULL,
	`interest_rate` DECIMAL(5, 2) NOT NULL,
	`total_owed` INT NOT NULL,
	`remaining_balance` INT NOT NULL,
	`installment_amount` INT NOT NULL,
	`installment_interval_seconds` INT UNSIGNED NOT NULL,
	`next_payment_due` TIMESTAMP NOT NULL,
	`missed_payments` TINYINT UNSIGNED NOT NULL DEFAULT 0,
	`auto_pay` TINYINT(1) NOT NULL DEFAULT 1,
	`status` ENUM('active', 'paid_off', 'defaulted', 'cancelled') NOT NULL DEFAULT 'active',
	-- When the loan stopped being active, so the history can say WHEN it was
	-- paid off rather than only that it was.
	`closed_at` TIMESTAMP NULL DEFAULT NULL,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `tb_loans_borrower_idx` (`borrower_identifier`, `status`),
	KEY `tb_loans_due_idx` (`status`, `next_payment_due`),
	CONSTRAINT `tb_loans_account_fk` FOREIGN KEY (`account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `tb_loan_payments` (
	`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	`loan_id` INT UNSIGNED NOT NULL,
	`amount` INT NOT NULL,
	`is_automatic` TINYINT(1) NOT NULL DEFAULT 0,
	`missed` TINYINT(1) NOT NULL DEFAULT 0,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `tb_loan_payments_loan_idx` (`loan_id`, `created_at`),
	CONSTRAINT `tb_loan_payments_loan_fk` FOREIGN KEY (`loan_id`) REFERENCES `tb_loans` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_tax_records
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_tax_records` (
	`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	`account_id` INT UNSIGNED NOT NULL,
	`taxable_amount` INT NOT NULL,
	`tax_amount` INT NOT NULL,
	`rate_applied` DECIMAL(5, 2) NOT NULL,
	`bracket_label` VARCHAR(64) DEFAULT NULL,
	`treasury_account_id` INT UNSIGNED DEFAULT NULL,
	`kind` VARCHAR(16) NOT NULL DEFAULT 'deposit',
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `tb_tax_records_account_idx` (`account_id`, `created_at`),
	CONSTRAINT `tb_tax_records_account_fk` FOREIGN KEY (`account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE CASCADE,
	CONSTRAINT `tb_tax_records_treasury_fk` FOREIGN KEY (`treasury_account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- tb_invoices: sender requests payment from recipient; paying moves money
-- recipient -> sender. Either side may be a personal account or a business.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tb_invoices` (
	`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`sender_account_id` INT UNSIGNED NOT NULL,
	`recipient_account_id` INT UNSIGNED NOT NULL,
	`amount` INT NOT NULL,
	`reason` VARCHAR(255) DEFAULT NULL,
	`status` ENUM('pending', 'paid', 'declined', 'overdue', 'cancelled') NOT NULL DEFAULT 'pending',
	`due_at` TIMESTAMP NULL DEFAULT NULL,
	`created_by` VARCHAR(64) DEFAULT NULL,
	`share_percent` TINYINT UNSIGNED NOT NULL DEFAULT 0,
	`share_account_id` INT UNSIGNED DEFAULT NULL,
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	`resolved_at` TIMESTAMP NULL DEFAULT NULL,
	PRIMARY KEY (`id`),
	KEY `tb_invoices_recipient_idx` (`recipient_account_id`, `status`),
	KEY `tb_invoices_sender_idx` (`sender_account_id`, `status`),
	CONSTRAINT `tb_invoices_sender_fk` FOREIGN KEY (`sender_account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE CASCADE,
	CONSTRAINT `tb_invoices_recipient_fk` FOREIGN KEY (`recipient_account_id`) REFERENCES `tb_accounts` (`id`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
]==]
