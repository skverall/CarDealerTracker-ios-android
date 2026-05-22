import { DEFAULT_LOCALE } from "./locale";
import type { Device, ProjectState, Slide } from "./types";

let _id = 0;
export const nid = () => `s_${Date.now().toString(36)}_${(_id++).toString(36)}`;

const en = (s: string) => ({ [DEFAULT_LOCALE]: s });
const copy = (english: string, japanese: string) => ({ en: english, ja: japanese });

function iphoneStarter(): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: copy("FOR CAR DEALERS", "中古車販売店向け"),
      headline: copy("Run your dealership\nfrom one place.", "在庫も利益も\nひと目で管理"),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: copy("INVENTORY", "車両管理"),
      headline: copy("See every car\nat a glance.", "販売中の車を\nすばやく確認"),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "two-devices",
      label: copy("PROFIT", "利益管理"),
      headline: copy("Know the real\nprofit per car.", "仕入れから売上まで\n数字を逃さない"),
      screenshot: "",
      screenshotSecondary: "",
    },
    {
      id: nid(),
      layout: "device-top",
      label: copy("EXPENSES", "経費"),
      headline: copy("Track costs\nas they happen.", "日々の経費を\nその場で記録"),
      screenshot: "",
      inverted: true,
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: copy("CLIENTS", "顧客管理"),
      headline: copy("Never miss\na follow-up.", "見込み客の対応を\n忘れない"),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "no-device",
      label: copy("MORE", "さらに"),
      headline: copy("Inventory\nExpenses\nSales\nClients\nTeam", "在庫\n経費\n売上\n顧客\nチーム"),
      screenshot: "",
    },
  ];
}

function ipadStarter(): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: copy("FOR SHOWROOMS", "店舗管理"),
      headline: copy("A clear view\nof the whole lot.", "店舗全体を\n大きく見える化"),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: copy("DASHBOARD", "ダッシュボード"),
      headline: copy("Check sales,\ncosts, and stock.", "売上・経費・在庫を\nまとめて確認"),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "device-top",
      label: copy("REPORTS", "レポート"),
      headline: copy("Monthly reports\nwithout the mess.", "月次レポートを\nすぐに確認"),
      screenshot: "",
      inverted: true,
    },
  ];
}

function tabletStarter(kind: "7" | "10"): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: en("CAR DEALER TRACKER"),
      headline: en(kind === "7" ? "Pocket-sized\npower." : "Made for\nthe big screen."),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "split-landscape",
      label: en("FEATURE 01"),
      headline: en("Wide canvas,\nbigger ideas."),
      screenshot: "",
    },
  ];
}

function fgStarter(): Slide[] {
  return [
    {
      id: nid(),
      layout: "feature-graphic",
      label: {},
      headline: copy("Dealership control for inventory, sales, and profit.", "在庫、売上、利益をひとつのアプリで管理。"),
      screenshot: "",
    },
  ];
}

export const DEFAULT_PROJECT: ProjectState = {
  appName: "Car Dealer Tracker",
  themeId: "clean-light",
  locales: ["ja", "en"],
  locale: "ja",
  device: "iphone",
  orientation: "portrait",
  appIcon: "/app-icon.png",
  slidesByDevice: {
    iphone: iphoneStarter(),
    android: iphoneStarter(),
    ipad: ipadStarter(),
    "android-7": tabletStarter("7"),
    "android-10": tabletStarter("10"),
    "feature-graphic": fgStarter(),
  },
};

export function newSlide(layout: Slide["layout"] = "device-bottom"): Slide {
  return {
    id: nid(),
    layout,
    label: en("NEW"),
    headline: en("Edit this\nheadline."),
    screenshot: "",
  };
}

export function detectPlatform(device: Device): "ios" | "android" {
  return device === "iphone" || device === "ipad" ? "ios" : "android";
}
