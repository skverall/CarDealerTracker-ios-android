import SwiftUI

struct UserGuideView: View {
    @EnvironmentObject private var regionSettings: RegionSettingsManager

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundColor(ColorTheme.primaryText)
                        ForEach(section.items, id: \.self) { item in
                            Text("- \(item)")
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 12)
            }
            .padding(.bottom, 24)
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationTitle("user_guide".localizedString)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sections: [GuideSection] {
        switch regionSettings.selectedLanguage {
        case .russian:
            return russianSections
        default:
            return englishSections
        }
    }

    private var englishSections: [GuideSection] {
        [
            GuideSection(
                title: "Quick Start",
                items: [
                    "Sign in or create a dealer organization.",
                    "Set region, currency, and language in Accounts > Region.",
                    "Add your first vehicle from Vehicles.",
                    "Invite teammates from Accounts > Team Management."
                ]
            ),
            GuideSection(
                title: "Navigation",
                items: [
                    "Bottom tabs: Dashboard, Expenses, Vehicles, Parts, Sales, Clients.",
                    "Use search in lists to filter by make/model, customer, or notes.",
                    "Pull to refresh to force a sync when online."
                ]
            ),
            GuideSection(
                title: "Vehicles & Inventory",
                items: [
                    "Vehicles are the core inventory records.",
                    "Statuses include on sale, reserved, in transit, under service, sold.",
                    "Edit a vehicle to update pricing, mileage, notes, and status.",
                    "Marking a vehicle as sold creates a sale record.",
                    "Use the Share button to generate a public vehicle link."
                ]
            ),
            GuideSection(
                title: "Vehicle Photos",
                items: [
                    "Edit a vehicle and tap Add Photos to select multiple images.",
                    "Review and upload in batch; optionally set the first photo as the cover.",
                    "Long-press a thumbnail to set it as cover or delete it.",
                    "Cover photo is used in lists and share links."
                ]
            ),
            GuideSection(
                title: "Holding Cost (Burning Inventory)",
                items: [
                    "Holding cost estimates daily carrying cost based on purchase price and expenses.",
                    "Configure annual rate in Accounts > Holding Cost Settings.",
                    "If you don't need it, you can turn it off in Accounts > Holding Cost Settings.",
                    "Holding cost accrues until the sale date; after sale it stops.",
                    "Sales profit includes holding cost."
                ]
            ),
            GuideSection(
                title: "Expenses",
                items: [
                    "Log expenses by category and link to a vehicle when applicable.",
                    "Vehicle expenses impact profit and holding cost base."
                ]
            ),
            GuideSection(
                title: "Sales (Vehicles)",
                items: [
                    "Sales are created when a vehicle is marked sold.",
                    "Sale account receives the funds and balance updates.",
                    "Profit = sale price - (purchase + expenses + holding cost) + VAT refund."
                ]
            ),
            GuideSection(
                title: "Parts Inventory & Sales",
                items: [
                    "Track parts inventory, receive stock, and sell parts.",
                    "Part sales track line items and cost of goods for profit."
                ]
            ),
            GuideSection(
                title: "Clients / CRM",
                items: [
                    "Store client details and link to sales and debts.",
                    "Search by name, phone, and notes."
                ]
            ),
            GuideSection(
                title: "Debts",
                items: [
                    "Record money owed to you or that you owe.",
                    "Mark payments to reduce outstanding balance."
                ]
            ),
            GuideSection(
                title: "Analytics & Alerts",
                items: [
                    "Inventory health uses aging, ROI, and holding cost.",
                    "Burning inventory highlights slow-moving vehicles.",
                    "Alerts trigger based on thresholds and recommendations."
                ]
            ),
            GuideSection(
                title: "Sync & Offline",
                items: [
                    "Local-first: changes save instantly and sync in background.",
                    "Manual Sync is available in Accounts.",
                    "Data Health and Deduplicate help clean up duplicates."
                ]
            ),
            GuideSection(
                title: "Team & Permissions",
                items: [
                    "Roles control access to costs, profit, and management tools.",
                    "Owners can manage team members and permissions."
                ]
            ),
            GuideSection(
                title: "Security & Legal",
                items: [
                    "Change password in Accounts.",
                    "Terms of Use and Privacy Policy are in Accounts."
                ]
            ),
            GuideSection(
                title: "Troubleshooting",
                items: [
                    "If photos or data do not appear, pull to refresh or run Sync Now.",
                    "If a vehicle looks duplicated, run Deduplicate.",
                    "Contact support from Accounts > Contact Developer."
                ]
            )
        ]
    }

    private var russianSections: [GuideSection] {
        [
            GuideSection(
                title: "Быстрый старт",
                items: [
                    "Войдите в аккаунт или создайте организацию дилера.",
                    "Настройте регион, валюту и язык в разделе Accounts > Region.",
                    "Добавьте первый автомобиль в разделе Vehicles.",
                    "Пригласите команду через Accounts > Team Management."
                ]
            ),
            GuideSection(
                title: "Навигация",
                items: [
                    "Нижние вкладки: Dashboard, Expenses, Vehicles, Parts, Sales, Clients.",
                    "Используйте поиск в списках по марке, модели, клиенту или заметкам.",
                    "Потяните список вниз для принудительной синхронизации."
                ]
            ),
            GuideSection(
                title: "Автомобили и склад",
                items: [
                    "Автомобили — основные записи склада.",
                    "Статусы: в продаже, зарезервирован, в пути, на сервисе, продан.",
                    "В режиме редактирования можно менять цены, пробег, заметки и статус.",
                    "Статус «продан» создает запись продажи.",
                    "Кнопка Share создаёт публичную ссылку на автомобиль."
                ]
            ),
            GuideSection(
                title: "Фотографии автомобиля",
                items: [
                    "В режиме редактирования нажмите Add Photos и выберите несколько фото.",
                    "Проверьте и загрузите пакетно; при необходимости первое фото станет обложкой.",
                    "Долгое нажатие на миниатюре позволяет сделать ее обложкой или удалить.",
                    "Обложка используется в списках и при шеринге."
                ]
            ),
            GuideSection(
                title: "Holding Cost (Burning Inventory)",
                items: [
                    "Holding cost — ежедневная стоимость простоя на основе цены покупки и расходов.",
                    "Годовую ставку можно настроить в Accounts > Holding Cost Settings.",
                    "Если функция не нужна, её можно отключить в Accounts > Holding Cost Settings.",
                    "Начисление идет до даты продажи; после продажи останавливается.",
                    "Прибыль в Sales включает holding cost."
                ]
            ),
            GuideSection(
                title: "Расходы",
                items: [
                    "Добавляйте расходы по категориям и привязывайте к авто, когда нужно.",
                    "Расходы по авто влияют на прибыль и базу для holding cost."
                ]
            ),
            GuideSection(
                title: "Продажи (авто)",
                items: [
                    "Продажи создаются при переводе авто в статус «продан».",
                    "Сумма продажи зачисляется на выбранный счет.",
                    "Прибыль = цена продажи - (покупка + расходы + holding cost) + возврат НДС."
                ]
            ),
            GuideSection(
                title: "Запчасти и продажи запчастей",
                items: [
                    "Ведите склад запчастей, приходуйте и продавайте их.",
                    "Продажи запчастей учитывают себестоимость и прибыль."
                ]
            ),
            GuideSection(
                title: "Клиенты / CRM",
                items: [
                    "Храните контакты клиентов и привязывайте к продажам и долгам.",
                    "Поиск по имени, телефону и заметкам."
                ]
            ),
            GuideSection(
                title: "Долги",
                items: [
                    "Фиксируйте долги вам и ваши долги.",
                    "Отмечайте оплаты, чтобы уменьшать остаток."
                ]
            ),
            GuideSection(
                title: "Аналитика и алерты",
                items: [
                    "Здоровье склада учитывает старение, ROI и holding cost.",
                    "Burning inventory показывает медленно продаваемые авто.",
                    "Алерты формируются по порогам и рекомендациям."
                ]
            ),
            GuideSection(
                title: "Синхронизация и офлайн",
                items: [
                    "Local-first: изменения сохраняются сразу и синхронизируются в фоне.",
                    "Ручная синхронизация доступна в Accounts.",
                    "Data Health и Deduplicate помогают чистить дубликаты."
                ]
            ),
            GuideSection(
                title: "Команда и права",
                items: [
                    "Роли управляют доступом к стоимости, прибыли и управлению.",
                    "Owner может управлять командой и правами."
                ]
            ),
            GuideSection(
                title: "Безопасность и правовые документы",
                items: [
                    "Смена пароля — в Accounts.",
                    "Terms of Use и Privacy Policy — в Accounts."
                ]
            ),
            GuideSection(
                title: "Диагностика",
                items: [
                    "Если фото или данные не отображаются, обновите список или запустите Sync Now.",
                    "Если видите дубликаты, запустите Deduplicate.",
                    "Поддержка доступна через Accounts > Contact Developer."
                ]
            )
        ]
    }
}

private struct GuideSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}
