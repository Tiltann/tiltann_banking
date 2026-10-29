# Changelog

## 1.1.0

- Fix: you could not bill yourself. You were missing from your own nearby player list, and a bill from an account to the same account was rejected with "Invalid amount or recipient".
- Invoices: new setting `Config.Billing.AllowSelfBilling` (default `true`). You appear in your own nearby list and can bill your own account, including from your personal account to itself. Paying such a bill moves no money, it is just settled.
- Invoices: with `AllowSelfBilling = false`, billing an account to itself now answers "You cannot bill an account to itself" (new `error.billing_same_account` text in en / de) instead of "Invalid amount or recipient".

## 1.0.0

- Initial release.
- ATM screen
- Invoices: past invoices list, invoice number, account number and sender name shown, billing from business accounts.
- Tablet and ATM open/close animation.
- Single target per bank counter (ped or zone), marker fallback without ox_target.
- Admin commands `/banksociety` and `/banksocietyleave` for testing businesses.
- Update check at resource start.
