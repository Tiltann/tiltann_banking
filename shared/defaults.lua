-- Fallback values for anything config/config.lua leaves out.
-- Edit config/config.lua instead of this file where you can.

local defaults = {
	Framework = 'auto',
	Admin = { Group = 'admin' },
	Language = 'en',
	Inventory = 'ox_inventory',

	UI = {
		CurrencySymbol = '$',
		Languages = { 'en', 'de' }, -- files in locales/ui/ sent to the UI
		Colors = {
			primary = '#1c1f26',
			secondary = '#2a2e37',
			accent = '#4f8cff',
			background = '#111319',
			surface = '#1a1d24',
			textPrimary = '#f2f3f5',
			textMuted = '#8b909c',
			success = '#3ecf8e',
			danger = '#e5484d',
			warning = '#e5a83d',
		},
	},

	Interaction = { Mode = 'auto', Key = 38, HelpText = false }, -- 'auto' | 'target' | 'helpnotification' | 'custom'

	Accounts = {
		Max = 3,
		NewAccountPrice = 1000,
		StartBalance = { First = 2500, Other = 500 },
		FeeToBalance = 0.5, -- share of the opening fee that is credited to the new account
		ClearingNumber = '920',
		MaxNameLength = 25,
	},

	Limits = {
		MinTransactionAmount = 1,
		MaxTransactionAmount = 500000,
		DailyWithdrawMax = 250000,
	},

	-- Poll interval for balance changes other scripts make through ESX's own
	-- bank account or esx_addonaccount / esx_society.
	Bridge = {
		PollIntervalMs = 15000,
		-- What happens when the balance is changed outside the bank (admin command,
		-- other script): 'entry' books the difference as an add or remove,
		-- 'clear' wipes the account's history and starts over, but only for jumps of
		-- at least ClearThreshold. Smaller ones (paychecks) stay normal entries.
		ExternalChange = 'entry',
		ClearThreshold = 5000,
		ForceDisabled = { player = false, society = false },
	},

	Atm = {
		UseExistingProps = true,
		PropModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' },
		Locations = {},
		InteractDistance = 2.0,
		QuickWithdraw = { 500, 1000, 1500, 3000, 5000, 7500 },
		PinLockoutAttempts = 3,
	},

	Bank = {
		Zones = {},
		SpawnPeds = true,
		Peds = {},
		TerminalInteractDistance = 2.0,
		Blips = { Enabled = true, Label = 'Bank', Sprite = 108, Colour = 2, Scale = 0.55, Display = 4, ShortRange = true, Locations = {} },
		AtmBlips = { Enabled = false, Label = 'ATM', Sprite = 108, Colour = 39, Scale = 0.35, Display = 4, ShortRange = true, Coords = {} },
	},

	-- Job grades without an override row get DefaultGradeRole. The top grade
	-- of a job is always owner.
	Society = {
		DefaultGradeRole = 'contributor',
		HighestGradeIsOwner = true,
		RoleCapabilities = {
			contributor = { view = true, deposit = true, withdraw = false, manageStaff = false, invoice = false, delete = false },
			admin = { view = true, deposit = true, withdraw = true, manageStaff = true, invoice = true, delete = false },
			owner = { view = true, deposit = true, withdraw = true, manageStaff = true, invoice = true, delete = true },
		},
	},

	Cards = {
		Enabled = true,
		ItemName = 'mastercard',
		AllowMultiplePerAccount = true,
		MaxPerAccount = 3, -- cards one player may hold for the same account

		ReplacementFee = 500,
		MinPinLength = 4,
		MaxPinLength = 6,
		AllowWeakPins = false, -- true lets players pick 1234, 1111, 1212 and so on
		DenylistedPins = { '2580', '1357', '2468', '1004', '6969', '4200', '0420' }, -- extra, on top of the pattern checks
		DefaultStaffDailyLimit = 25000, -- company card limit when staff has none set
	},

	-- Interest is a percent of the balance per interval. Money can't leave
	-- for WithdrawLockSeconds after a deposit (0 = no lock).
	Savings = {
		Enabled = true,
		MaxSavingsAccounts = 2,
		NewAccountPrice = 1000,
		StartBalance = 0,
		InterestRate = 1.5,
		IntervalSeconds = 86400,
		WithdrawLockSeconds = 7 * 86400,
		MinBalanceForInterest = 100,
		MaxInterestPerTick = 50000,
		CheckIntervalMs = 300000,
	},

	StandingOrders = {
		Enabled = true,
		MaxPerAccount = 10,
		MinIntervalSeconds = 3600,
		MaxFailedRuns = 3, -- switched off after this many failed runs in a row
		AllowFromSavings = false,
		CheckIntervalMs = 60000,
	},

	-- Interest is applied once to the principal and split into installments.
	Loans = {
		Enabled = true,
		MinLoanAmount = 1000,
		MaxLoanAmount = 100000,
		Presets = { 5000, 10000, 25000, 50000, 100000 },
		InterestRate = 8.5,
		InstallmentCount = 10,
		InstallmentIntervalSeconds = 604800,
		MaxMissedPayments = 3,
		CheckIntervalMs = 300000,
		AllowSocietyLoans = false,
	},

	-- Mode is 'flat' or 'bracket'. Destination.Type is 'society' (a job's
	-- business account), 'account' (set AccountNumber) or 'burn'.
	Tax = {
		Enabled = false,
		Mode = 'flat',
		FlatRate = 5.0,
		Brackets = {
			{ min = 0, max = 5000, rate = 2.0 },
			{ min = 5000, max = 25000, rate = 5.0 },
			{ min = 25000, max = nil, rate = 8.0 },
		},
		MinTaxableAmount = 100,
		SummaryPeriodDays = 30,
		ApplyOn = { deposit = true, withdraw = false, transfer = false },
		PeriodicBalanceTax = { Enabled = false, IntervalMs = 3600000, Rate = 0.5 },
		Destination = { Type = 'society', Job = 'government', AccountNumber = nil, Label = 'Treasury' },
	},

	Transactions = {
		AllowClearHistory = true,
	},

	Billing = {
		Enabled = true,
		Key = 'F7',
		MaxPersonalSharePercent = 50, -- most of a business bill the biller may keep
		NearbyRadius = 10.0, -- how far the billing menu looks for players
		MaxOpenInvoicesPerSender = 20,
		DefaultDueDays = 7,
		AllowSocietyToSociety = true,
		OverdueSweepIntervalMs = 600000,
		AutoChargeOnOverdue = true, -- unpaid bills are taken on the due date, even into the negative
	},

	Logs = {
		BotName = 'Tiltann Banking',
		Webhook = '', -- one Discord webhook for every category
		SecurityWebhook = '', -- optional second channel for security alerts and large amounts
		Debug = false,
		Console = { Level = 'info', Ledger = false }, -- Ledger = print every money movement
		OxLogger = { Enabled = true },
		Colors = { success = 0x3ecf8e, danger = 0xe5484d, warning = 0xe5a83d, info = 0x4f8cff },
		LargeTransactionThreshold = 50000, -- also posts to security_alerts
		Enabled = {
			deposits = true,
			withdrawals = true,
			transfers = true,
			cards = true,
			loans = true,
			tax = true,
			billing = true,
			admin_actions = true,
			society_sync = false,
			security_alerts = true,
		},
		WebhookURLs = {}, -- optional per category override, e.g. { cards = 'https://...' }
	},

	Updater = {
		Enabled = true,
		Repository = nil, -- defaults to `repository` in fxmanifest.lua
		NotifyAdmins = true,
		MaxNotesLength = 700,
	},

	Database = {
		AutoMigrate = true,
		HaltOnIncompleteSchema = true,
		ConnectTimeoutSeconds = 60,
	},
}

local function isList(t)
	return type(t) == 'table' and t[1] ~= nil
end

local function fill(target, source)
	for key, value in pairs(source) do
		local current = target[key]
		if current == nil then
			target[key] = value
		elseif type(current) == 'table' and type(value) == 'table' and not isList(value) then
			fill(current, value)
		end
	end
end

fill(Config, defaults)

-- Config.Language is the one setting; the UI reads it under its old name.
Config.UI.DefaultLanguage = Config.UI.DefaultLanguage or Config.Language

-- Config.Bank.Blips = true/false is shorthand for Blips.Enabled.
if type(Config.Bank.Blips) == 'boolean' then
	Config.Bank.Blips = { Enabled = Config.Bank.Blips }
	fill(Config.Bank.Blips, defaults.Bank.Blips)
end
