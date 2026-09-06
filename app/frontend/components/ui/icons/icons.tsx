import * as React from 'react';
import {
  Add01FreeIcons,
  Alert01FreeIcons,
  AlertCircleFreeIcons,
  ArrowDown01FreeIcons,
  ArrowUpDownFreeIcons,
  BookOpen01FreeIcons,
  Calendar03FreeIcons,
  Cancel01FreeIcons,
  CancelCircleFreeIcons,
  CheckCheckFreeIcons,
  CheckmarkCircle02FreeIcons,
  ChevronDownFreeIcons,
  ChevronLeftFreeIcons,
  ChevronRightFreeIcons,
  ChevronUpFreeIcons,
  ClipboardFreeIcons,
  CloudUploadFreeIcons,
  CouponPercentFreeIcons,
  CreditCardFreeIcons,
  DashboardSpeed01FreeIcons,
  Edit01FreeIcons,
  File01FreeIcons,
  File02FreeIcons,
  FileCodeFreeIcons,
  FileZipFreeIcons,
  Folder02FreeIcons,
  FolderMusicFreeIcons,
  FolderOpenFreeIcons,
  GridTableFreeIcons,
  GripVerticalFreeIcons,
  Home01FreeIcons,
  Image02FreeIcons,
  Loading03FreeIcons,
  Mail01FreeIcons,
  Menu01FreeIcons,
  MinusSignFreeIcons,
  MoreHorizontalFreeIcons,
  Notification02FreeIcons,
  PackageFreeIcons,
  PanelLeftCloseFreeIcons,
  PlayFreeIcons,
  RefreshFreeIcons,
  Rocket01FreeIcons,
  Search01FreeIcons,
  SecurityCheckFreeIcons,
  Settings02FreeIcons,
  SmileFreeIcons,
  SlidersHorizontalFreeIcons,
  StarFreeIcons,
  TextSquareFreeIcons,
  Tick02FreeIcons,
  Upload01FreeIcons,
  UserCircleFreeIcons,
  ViewFreeIcons,
  ViewOffSlashFreeIcons,
} from '@hugeicons/core-free-icons';
import { HugeiconsIcon, type IconSvgElement } from '@hugeicons/react';

export type IconProps = React.SVGProps<SVGSVGElement> & {
  size?: string | number;
};

function createHugeicon(icon: IconSvgElement, displayName: string) {
  const Icon = React.forwardRef<SVGSVGElement, IconProps>(
    ({ size = 18, strokeWidth = 1.5, ...props }, ref) => {
      const normalizedStrokeWidth =
        typeof strokeWidth === 'number' ? strokeWidth : Number.parseFloat(strokeWidth) || 1.5;

      return (
        <HugeiconsIcon
          ref={ref}
          icon={icon}
          size={size}
          strokeWidth={normalizedStrokeWidth}
          aria-hidden={props['aria-label'] ? undefined : true}
          {...props}
        />
      );
    },
  );

  Icon.displayName = displayName;
  return Icon;
}

/**
 * Registro padrão de ícones estáticos da biblioteca, baseado em Hugeicons.
 * Line MD continua exportado separadamente para usos manuais e pontuais.
 */
export const Icons = {
  account: createHugeicon(UserCircleFreeIcons, 'AccountIcon'),
  actions: createHugeicon(MoreHorizontalFreeIcons, 'ActionsIcon'),
  alert: createHugeicon(Alert01FreeIcons, 'AlertIcon'),
  alertCircle: createHugeicon(AlertCircleFreeIcons, 'AlertCircleIcon'),
  arrowDown: createHugeicon(ArrowDown01FreeIcons, 'ArrowDownIcon'),
  arrowsVertical: createHugeicon(ArrowUpDownFreeIcons, 'ArrowsVerticalIcon'),
  book: createHugeicon(BookOpen01FreeIcons, 'BookIcon'),
  calendar: createHugeicon(Calendar03FreeIcons, 'CalendarIcon'),
  checkAll: createHugeicon(CheckCheckFreeIcons, 'CheckAllIcon'),
  chevronDown: createHugeicon(ChevronDownFreeIcons, 'ChevronDownIcon'),
  chevronLeft: createHugeicon(ChevronLeftFreeIcons, 'ChevronLeftIcon'),
  chevronRight: createHugeicon(ChevronRightFreeIcons, 'ChevronRightIcon'),
  chevronUp: createHugeicon(ChevronUpFreeIcons, 'ChevronUpIcon'),
  clipboard: createHugeicon(ClipboardFreeIcons, 'ClipboardIcon'),
  close: createHugeicon(Cancel01FreeIcons, 'CloseIcon'),
  closeCircle: createHugeicon(CancelCircleFreeIcons, 'CloseCircleIcon'),
  cloudUpload: createHugeicon(CloudUploadFreeIcons, 'CloudUploadIcon'),
  cog: createHugeicon(Settings02FreeIcons, 'CogIcon'),
  columns: createHugeicon(SlidersHorizontalFreeIcons, 'ColumnsIcon'),
  component: createHugeicon(PackageFreeIcons, 'ComponentIcon'),
  confirm: createHugeicon(Tick02FreeIcons, 'ConfirmIcon'),
  confirmCircle: createHugeicon(CheckmarkCircle02FreeIcons, 'ConfirmCircleIcon'),
  coupon: createHugeicon(CouponPercentFreeIcons, 'CouponIcon'),
  creditCard: createHugeicon(CreditCardFreeIcons, 'CreditCardIcon'),
  documentCode: createHugeicon(FileCodeFreeIcons, 'DocumentCodeIcon'),
  drag: createHugeicon(GripVerticalFreeIcons, 'DragIcon'),
  edit: createHugeicon(Edit01FreeIcons, 'EditIcon'),
  email: createHugeicon(Mail01FreeIcons, 'EmailIcon'),
  emojiSmile: createHugeicon(SmileFreeIcons, 'EmojiSmileIcon'),
  eye: createHugeicon(ViewFreeIcons, 'EyeIcon'),
  eyeOff: createHugeicon(ViewOffSlashFreeIcons, 'EyeOffIcon'),
  file: createHugeicon(File01FreeIcons, 'FileIcon'),
  fileDocument: createHugeicon(File02FreeIcons, 'FileDocumentIcon'),
  folderMusic: createHugeicon(FolderMusicFreeIcons, 'FolderMusicIcon'),
  folderOpen: createHugeicon(FolderOpenFreeIcons, 'FolderOpenIcon'),
  folderTwotone: createHugeicon(Folder02FreeIcons, 'FolderIcon'),
  folderZip: createHugeicon(FileZipFreeIcons, 'FolderZipIcon'),
  grid: createHugeicon(GridTableFreeIcons, 'GridIcon'),
  home: createHugeicon(Home01FreeIcons, 'HomeIcon'),
  image: createHugeicon(Image02FreeIcons, 'ImageIcon'),
  loading: createHugeicon(Loading03FreeIcons, 'LoadingIcon'),
  logo: (props: React.SVGProps<SVGSVGElement>) => (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      width={18}
      height={18}
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden={props['aria-label'] ? undefined : true}
      {...props}
    >
      <path d="M2.5 16.88a1 1 0 0 1-.32-1.43l9-13.02a1 1 0 0 1 1.64 0l9 13.01a1 1 0 0 1-.32 1.44l-8.51 4.86a2 2 0 0 1-1.98 0Z" />
      <path d="M12 2v20" />
    </svg>
  ),
  menu: createHugeicon(Menu01FreeIcons, 'MenuIcon'),
  menuFoldLeft: createHugeicon(PanelLeftCloseFreeIcons, 'MenuFoldLeftIcon'),
  minus: createHugeicon(MinusSignFreeIcons, 'MinusIcon'),
  notification: createHugeicon(Notification02FreeIcons, 'NotificationIcon'),
  play: createHugeicon(PlayFreeIcons, 'PlayIcon'),
  plus: createHugeicon(Add01FreeIcons, 'PlusIcon'),
  rotate: createHugeicon(RefreshFreeIcons, 'RotateIcon'),
  rocket: createHugeicon(Rocket01FreeIcons, 'RocketIcon'),
  search: createHugeicon(Search01FreeIcons, 'SearchIcon'),
  securityCheck: createHugeicon(SecurityCheckFreeIcons, 'SecurityCheckIcon'),
  speed: createHugeicon(DashboardSpeed01FreeIcons, 'SpeedIcon'),
  spinner: createHugeicon(Loading03FreeIcons, 'SpinnerIcon'),
  star: createHugeicon(StarFreeIcons, 'StarIcon'),
  textBox: createHugeicon(TextSquareFreeIcons, 'TextBoxIcon'),
  upload: createHugeicon(Upload01FreeIcons, 'UploadIcon'),
} as const;

export type IconName = keyof typeof Icons;
