/**
 * Icons come from lucide-react rather than hand-drawn SVG paths.
 *
 * lucide is stroke-based at a uniform 24x24 grid, which is what this UI was
 * already built around (one consistent stroke weight, `currentColor`), so
 * every existing call site keeps working unchanged, including the few that
 * pass `stroke` directly. The names below stay resource-specific (CardIcon,
 * LoanIcon) so a future swap to another pack is one edit in this file
 * instead of a rename across thirty components.
 */
import type { LucideIcon, LucideProps } from 'lucide-react';
import {
	ArrowDownToLine,
	ArrowLeftRight,
	ArrowUpFromLine,
	Building2,
	Check,
	ChevronDown,
	ChevronRight,
	Copy,
	CreditCard,
	Globe,
	HandCoins,
	LayoutDashboard,
	List,
	ListFilter,
	Lock,
	Palette,
	Percent,
	Plus,
	ReceiptText,
	RefreshCw,
	Repeat,
	Send,
	Settings,
	Star,
	Trash2,
	TriangleAlert,
	Unlock,
	Users,
	Wallet,
	X,
} from 'lucide-react';

/**
 * Call sites size icons with width/height (`<WalletIcon width={15} />`),
 * which lucide also accepts; `size` is only a shorthand for both. Passing
 * width without height is the common case here, so mirror it rather than
 * leaving a 24px-tall icon in a 15px-wide box.
 */
export type IconProps = LucideProps;

function icon(Component: LucideIcon) {
	return function Icon({ width, height, strokeWidth = 1.75, ...rest }: IconProps) {
		return <Component width={width ?? height} height={height ?? width} strokeWidth={strokeWidth} {...rest} />;
	};
}

export const WalletIcon = icon(Wallet);
export const BuildingIcon = icon(Building2);
export const CloseIcon = icon(X);
export const GearIcon = icon(Settings);
export const DepositIcon = icon(ArrowDownToLine);
export const WithdrawIcon = icon(ArrowUpFromLine);
export const TransferIcon = icon(ArrowLeftRight);
export const CardIcon = icon(CreditCard);
export const LockIcon = icon(Lock);
export const UnlockIcon = icon(Unlock);
export const AlertIcon = icon(TriangleAlert);
export const LoanIcon = icon(HandCoins);
export const InvoiceIcon = icon(ReceiptText);
export const CheckIcon = icon(Check);
export const SendIcon = icon(Send);
export const GlobeIcon = icon(Globe);
export const PaletteIcon = icon(Palette);
export const UsersIcon = icon(Users);
export const ChevronRightIcon = icon(ChevronRight);
export const ChevronDownIcon = icon(ChevronDown);
export const DashboardIcon = icon(LayoutDashboard);
export const RepeatIcon = icon(Repeat);
export const PlusIcon = icon(Plus);
export const TrashIcon = icon(Trash2);
export const StarIcon = icon(Star);
export const CopyIcon = icon(Copy);
export const FilterIcon = icon(ListFilter);
export const PercentIcon = icon(Percent);
export const ListIcon = icon(List);
export const RefreshIcon = icon(RefreshCw);
