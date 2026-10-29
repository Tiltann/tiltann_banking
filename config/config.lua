-- tiltann_banking config
--
-- This is the only file you need to edit. Every option you leave out falls
-- back to shared/defaults.lua, and any option from that file can be added
-- here to override it. Restart the resource after a change.

Config = {

	-- ------------------------------------------------------------------
	-- General
	-- ------------------------------------------------------------------

	-- Which player framework you run: 'auto' (detects it), 'esx', 'qb' or 'qbox'.
	-- Only ESX is tested. qb and qbox print a warning when used.
	Framework = 'auto',

	-- Language of the UI and the notifications: 'en' or 'de'.
	-- Players can switch the UI language themselves with the gear icon.
	Language = 'en',

	-- What happens to cards (the physical item):
	--   'ox_inventory'  players get a "Bank Card" item
	--   'none'          no item at all, cards only exist in the database
	--                   (use this for any other inventory or if you have no metadata)
	Inventory = 'ox_inventory',

	-- Who may use the admin commands (/tb_setbalance and so on).
	-- Players in this framework group are admins. The ace permission
	-- tiltann_banking.admin works as well, but you do not need it.
	-- Set Group = '' to only use the ace.
	Admin = {
		Group = 'admin',
	},

	UI = {
		CurrencySymbol = '$',
		Colors = {
			accent = '#4f8cff', -- main colour of the UI
		},
	},


	-- ------------------------------------------------------------------
	-- Interaction (how players use ATMs and bank terminals)
	-- ------------------------------------------------------------------

	Interaction = {
		-- 'auto'              ox_target if it is running, otherwise the help text
		-- 'target'            ox_target only
		-- 'helpnotification'  help text in the top left corner, press the key
		-- 'custom'            nothing is set up for you, write it in Custom below
		Mode = 'auto',

		-- Key for the help text. 38 = E
		Key = 38,

		-- true = show the help text and allow the key even when ox_target is used
		HelpText = false,

		-- Only used with Mode = 'custom'. This runs once on the client.
		-- openAtm(), openBank() and openBilling() open the screens.
		-- The ATM props are in Config.Atm.PropModels, the banks in Config.Bank.Zones.
		Custom = function(openAtm, openBank, openBilling) -- luacheck: ignore
			-- ADD YOUR OWN INTERACTION HERE, for example:
			-- exports['my_target']:AddTargetModel(Config.Atm.PropModels, { action = openAtm })
		end,
	},


	-- ------------------------------------------------------------------
	-- Accounts and limits
	-- ------------------------------------------------------------------

	Accounts = {
		Max = 3,                 -- personal accounts per player
		NewAccountPrice = 1000,  -- fee for opening another one
		FeeToBalance = 0.5,      -- share of that fee that lands on the new account (0.5 = half)

		StartBalance = {
			-- Money on the first account every player gets.
			-- false = no starting money from this script. Use it when your
			-- framework already gives money on start: the account then just
			-- takes over whatever the framework bank balance already is.
			First = 2500,

			-- Money on accounts opened later. 0 = empty.
			Other = 500,
		},
	},

	Limits = {
		MaxTransactionAmount = 500000,  -- biggest single deposit, withdrawal or transfer
		DailyWithdrawMax = 250000,      -- most a player can withdraw per day
	},

	-- What happens when the balance is changed outside the bank
	-- (an admin command like /setaccountmoney, or another script):
	--   'clear'  the account history is wiped and one "Balance reset" entry
	--            is written, but only for changes of ClearThreshold or more,
	--            so normal paychecks stay normal entries
	--   'entry'  the difference is always booked as an add or remove
	Bridge = {
		ExternalChange = 'clear',
		ClearThreshold = 5000,
	},

	Transactions = {
		-- Shows a "Clear history" button. It only hides the player's own
		-- statement, the rows stay in the database for limits and audits.
		AllowClearHistory = true,
	},


	-- ------------------------------------------------------------------
	-- ATMs
	-- ------------------------------------------------------------------

	Atm = {
		-- ATM props that already exist on the map. Add a model name to make
		-- more props usable. Target, help text and custom mode all use this list.
		UseExistingProps = true,
		PropModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' },

		-- The one tap withdraw buttons on the ATM screen.
		QuickWithdraw = { 500, 1000, 1500, 3000, 5000, 7500 },

		-- Wrong PINs in a row before the card is blocked.
		PinLockoutAttempts = 3,
	},


	-- ------------------------------------------------------------------
	-- Banks (copied from esx_banking)
	-- ------------------------------------------------------------------

	Bank = {
		-- Map blips. Every entry in Locations can override the defaults with
		-- its own sprite, colour, scale or label, for example:
		-- { coords = vector3(0.0, 0.0, 0.0), sprite = 207, colour = 5, label = 'Savings Bank' }
		Blips = {
			Enabled = true,
			Label = 'Bank',
			Sprite = 108,
			Colour = 2,
			Scale = 0.55,
			Display = 4,       -- 4 = shown on the map and the minimap
			ShortRange = true, -- only visible when close
			Locations = {
				{ coords = vector3(149.9, -1040.46, 29.37) },
				{ coords = vector3(314.23, -278.83, 54.17) },
				{ coords = vector3(-350.8, -49.57, 49.04) },
				{ coords = vector3(-1213.0, -330.39, 37.79) },
				{ coords = vector3(-2962.71, 483.0, 15.7) },
				{ coords = vector3(1175.07, 2706.41, 38.09) },
				{ coords = vector3(246.64, 223.2, 106.29) },
				{ coords = vector3(-113.22, 6470.03, 31.63) },
			},
		},

		-- Blips for every ATM, off by default because there are a lot of them.
		AtmBlips = {
			Enabled = false,
			Label = 'ATM',
			Sprite = 108,
			Colour = 39,
			Scale = 0.35,
			Display = 4,
			ShortRange = true,
			Coords = {
				vector3(-386.733, 6045.953, 31.501),
				vector3(-284.037, 6224.385, 31.187),
				vector3(-135.165, 6365.738, 31.101),
				vector3(-110.753, 6467.703, 31.784),
				vector3(-94.969, 6455.301, 31.784),
				vector3(155.43, 6641.991, 31.784),
				vector3(174.672, 6637.218, 31.784),
				vector3(1703.138, 6426.783, 32.73),
				vector3(1735.114, 6411.035, 35.164),
				vector3(1702.842, 4933.593, 42.051),
				vector3(1967.333, 3744.293, 32.272),
				vector3(1821.917, 3683.483, 34.244),
				vector3(540.042, 2671.007, 42.177),
				vector3(2564.399, 2585.1, 38.016),
				vector3(2558.683, 349.601, 108.05),
				vector3(2558.051, 389.4817, 108.66),
				vector3(1077.692, -775.796, 58.218),
				vector3(1139.018, -469.886, 66.789),
				vector3(1168.975, -457.241, 66.641),
				vector3(1153.884, -326.54, 69.245),
				vector3(381.2827, 323.2518, 103.27),
				vector3(236.4638, 217.4718, 106.84),
				vector3(265.0043, 212.1717, 106.78),
				vector3(285.2029, 143.569, 104.97),
				vector3(157.7698, 233.545, 106.45),
				vector3(-164.568, 233.5066, 94.919),
				vector3(-1827.04, 785.5159, 138.02),
				vector3(-1409.39, -99.2603, 52.473),
				vector3(-1205.35, -325.579, 37.87),
				vector3(-2072.41, -316.959, 13.345),
				vector3(-2975.72, 379.7737, 14.992),
				vector3(-2962.6, 482.1914, 15.762),
				vector3(-2955.7, 488.7218, 15.486),
				vector3(-3044.22, 595.2429, 7.595),
				vector3(-3144.13, 1127.415, 20.868),
				vector3(-3241.1, 996.6881, 12.5),
				vector3(-3241.11, 1009.152, 12.877),
				vector3(-1305.4, -706.24, 25.352),
				vector3(-538.225, -854.423, 29.234),
				vector3(-711.156, -818.958, 23.768),
				vector3(-717.614, -915.88, 19.268),
				vector3(-526.566, -1222.9, 18.434),
				vector3(-256.831, -719.646, 33.444),
				vector3(-203.548, -861.588, 30.205),
				vector3(112.4102, -776.162, 31.427),
				vector3(112.929, -818.71, 31.386),
				vector3(119.9, -883.826, 31.191),
				vector3(-846.304, -340.402, 38.687),
				vector3(-56.1935, -1752.53, 29.452),
				vector3(-261.692, -2012.64, 30.121),
				vector3(-273.001, -2025.6, 30.197),
				vector3(24.589, -946.056, 29.357),
				vector3(-254.112, -692.483, 33.616),
				vector3(-1570.2, -546.651, 34.955),
				vector3(-1415.91, -211.825, 46.5),
				vector3(-1430.11, -211.014, 46.5),
				vector3(33.232, -1347.85, 29.497),
				vector3(129.216, -1292.35, 29.269),
				vector3(287.645, -1282.646, 29.66),
				vector3(289.012, -1256.545, 29.44),
				vector3(295.839, -895.64, 29.217),
				vector3(1686.753, 4815.809, 42.008),
				vector3(-302.408, -829.945, 32.417),
				vector3(5.134, -919.949, 29.557),
			},
		},

		SpawnPeds = true,  -- bank clerks standing at the counters

		-- Where the terminal can be used. size = width, length, height of the
		-- box that ox_target uses, heading turns it.
		Zones = {
			{ coords = vector3(149.05, -1041.3, 29.37), heading = 250.0, size = vector3(2.0, 6.2, 4.0), label = 'Bank' },
			{ coords = vector3(313.32, -280.03, 54.17), heading = 250.0, size = vector3(2.0, 6.6, 4.0), label = 'Bank' },
			{ coords = vector3(-351.94, -50.72, 49.04), heading = 71.0, size = vector3(2.0, 6.4, 4.0), label = 'Bank' },
			{ coords = vector3(-1212.68, -331.83, 37.78), heading = 297.0, size = vector3(2.0, 6.4, 4.0), label = 'Bank' },
			{ coords = vector3(-2961.67, 482.31, 15.7), heading = 358.0, size = vector3(2.0, 6.6, 4.0), label = 'Bank' },
			{ coords = vector3(1175.64, 2707.71, 38.09), heading = 90.0, size = vector3(2.0, 6.6, 4.0), label = 'Bank' },
			{ coords = vector3(247.65, 223.87, 106.29), heading = 250.0, size = vector3(2.0, 15.8, 4.0), label = 'Bank' },
			{ coords = vector3(-111.98, 6470.56, 31.63), heading = 45.0, size = vector3(2.0, 6.6, 4.0), label = 'Bank' },
		},

		-- The bank clerks.
		Peds = {
			{ coords = vector4(149.5513, -1042.157, 29.368, 341.652), model = 'u_m_m_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD' },
			{ coords = vector4(-1211.8585, -331.9854, 37.7809, 28.5983), model = 'u_m_m_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD' },
			{ coords = vector4(-2961.072, 483.1107, 15.697, 88.1986), model = 'u_m_m_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD' },
			{ coords = vector4(-112.2223, 6471.1128, 31.6267, 132.7517), model = 'u_m_m_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD' },
			{ coords = vector4(313.8176, -280.5338, 54.1647, 339.1609), model = 'u_m_m_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD' },
			{ coords = vector4(-351.3247, -51.3466, 49.0365, 339.3305), model = 'u_m_m_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD' },
			{ coords = vector4(1174.9718, 2708.2034, 38.0879, 178.2974), model = 'u_m_m_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD' },
			{ coords = vector4(247.0348, 225.1851, 106.2875, 158.7528), model = 'u_m_m_bankman', scenario = 'WORLD_HUMAN_CLIPBOARD' },
		},
	},


	-- ------------------------------------------------------------------
	-- Bank cards
	-- ------------------------------------------------------------------

	Cards = {
		Enabled = true,
		ItemName = 'mastercard',  -- must match the item in ox_inventory
		ReplacementFee = 500,      -- price of a new card after reporting one lost
		MaxPerAccount = 3,         -- cards one player can hold for the same account

		-- PINs are 4 to 6 digits.
		-- false = easy PINs are refused, true = everything is allowed.
		--
		-- What counts as weak (edit this to your taste):
		--   * one digit repeated:      0000, 1111, 777777
		--   * a straight run of 4+:    1234, 4321, 56789   (code: IsWeakPin in server/cards/cards.lua)
		--   * a repeated block:        1212, 123123        (code: IsWeakPin in server/cards/cards.lua)
		--   * anything that contains an entry of the list below
		AllowWeakPins = false,

		-- Extra weak PINs. A PIN is refused if it contains one of these.
		-- Add your own or remove the ones you do not mind.
		DenylistedPins = { '2580', '1357', '2468', '1004', '6969', '4200', '0420' },
	},


	-- ------------------------------------------------------------------
	-- Savings accounts
	-- ------------------------------------------------------------------

	Savings = {
		Enabled = true,
		NewAccountPrice = 1000,   -- opening fee

		InterestRate = 1.5,       -- percent of the balance, paid every IntervalSeconds
		IntervalSeconds = 86400,  -- 86400 = once a day

		-- After every deposit the money is locked for this long.
		-- 7 * 86400 = 7 days, 0 = no lock.
		WithdrawLockSeconds = 7 * 86400,
	},


	-- ------------------------------------------------------------------
	-- Loans
	-- ------------------------------------------------------------------

	Loans = {
		Enabled = true,
		InterestRate = 8.5,      -- percent, added once to the loan
		MinLoanAmount = 1000,
		MaxLoanAmount = 100000,
	},


	-- ------------------------------------------------------------------
	-- Billing (bills between players and businesses)
	-- ------------------------------------------------------------------

	Billing = {
		Enabled = true,
		Key = 'F7',                    -- opens the billing menu, players can rebind it
		NearbyRadius = 10.0,           -- how far the menu looks for players to bill
		AllowSelfBilling = true,       -- you appear in your own nearby list and can bill your own account; paying such a bill moves no money, it is just settled

		-- A bill from a business can pay the biller a share. This is the most
		-- they can take (percent), the rest goes to the business.
		MaxPersonalSharePercent = 50,

		-- Days to pay a bill. A bill from a business cannot be declined: after
		-- the due date it is taken from the account automatically, even if the
		-- balance goes negative. A bill from a person can be declined and is
		-- never taken automatically.
		DefaultDueDays = 7,
		AutoChargeOnOverdue = true,    -- false = also business bills are only marked overdue
	},


	-- ------------------------------------------------------------------
	-- Standing orders (recurring transfers, for example rent)
	-- ------------------------------------------------------------------

	StandingOrders = {
		Enabled = true,
	},


	-- ------------------------------------------------------------------
	-- Tax (off by default)
	-- ------------------------------------------------------------------

	Tax = {
		Enabled = false,
		FlatRate = 5.0,  -- percent

		-- Where the collected tax goes:
		--   Type = 'society'  the business account of Job
		--   Type = 'account'  a fixed account, set AccountNumber = '920-12345678'
		--   Type = 'burn'     the money just disappears
		Destination = { Type = 'society', Job = 'government' },
	},


	-- ------------------------------------------------------------------
	-- Logs
	-- ------------------------------------------------------------------

	Logs = {
		-- One Discord webhook for everything. Every category has its own icon
		-- and colour, leave it empty to only log to the console.
		Webhook = '',

		-- Optional: security alerts and large amounts go here instead.
		SecurityWebhook = '',

		-- Prints every server callback, SQL query and tick. Also /tb_debug.
		Debug = false,
	},
}
