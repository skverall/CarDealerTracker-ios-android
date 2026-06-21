import SwiftUI

struct UserGuideView: View {
    @EnvironmentObject private var regionSettings: RegionSettingsManager

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    GuideSectionCard(section: section)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationTitle("user_guide".localizedString)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sections: [GuideSection] {
        switch regionSettings.selectedLanguage {
        case .portugueseBrazil:
            return portugueseBrazilSections
        case .russian:
            return russianSections
        case .uzbek:
            return uzbekSections
        default:
            return englishSections
        }
    }

    private var englishSections: [GuideSection] {
        [
            GuideSection(
                title: "Getting Started",
                items: [
                    "Sign in or create a dealer organization.",
                    "Open Account > Region & Language to choose your country, currency, language, and formats.",
                    "Use the theme switch in Account if you prefer light or dark mode.",
                    "Add your first vehicle from Vehicles, then create financial accounts if you want balances to update automatically.",
                    "Turn the Parts tab on or off from Account depending on whether your dealership sells parts."
                ]
            ),
            GuideSection(
                title: "Navigation",
                items: [
                    "Bottom tabs: Dashboard, Expenses, Vehicles, Parts, Sales, Clients.",
                    "Dashboard gives the fastest view of money, inventory, alerts, and shortcuts.",
                    "Use search in lists to find vehicles, clients, notes, VINs, and records faster.",
                    "Most detail screens open by tapping a row; go back with the iOS back button or swipe from the left edge."
                ]
            ),
            GuideSection(
                title: "Vehicles & Photos",
                items: [
                    "Vehicles are your main inventory records.",
                    "Statuses include on sale, reserved, in transit, under service, sold.",
                    "Edit a vehicle to update price, mileage, purchase details, notes, and status.",
                    "Marking a vehicle as sold creates a sale record.",
                    "Add multiple photos, set a cover photo, and use Share to create a public vehicle link."
                ]
            ),
            GuideSection(
                title: "Holding Cost (Burning Inventory)",
                items: [
                    "Holding cost estimates the daily cost of keeping a vehicle in stock.",
                    "Configure the annual rate in Account > Holding Cost Settings.",
                    "You can turn holding cost off if your dealership does not use it.",
                    "Holding cost accrues until the sale date; after sale it stops.",
                    "Sales profit includes holding cost."
                ]
            ),
            GuideSection(
                title: "Expenses & Financial Accounts",
                items: [
                    "Log vehicle, personal, and employee expenses by category.",
                    "Link an expense to a vehicle when it belongs to that vehicle.",
                    "Vehicle expenses affect vehicle profit and holding cost base.",
                    "Owners and admins can manage cash, bank, and credit accounts from Account > Financial Accounts.",
                    "When you choose an account for a sale or expense, the account balance updates."
                ]
            ),
            GuideSection(
                title: "Sales & Debts",
                items: [
                    "Create a vehicle sale by marking the vehicle as sold or recording a sale.",
                    "Select the receiving account so the money goes to the right balance.",
                    "Profit includes sale price, purchase price, expenses, holding cost, and VAT refund when used.",
                    "Use Debts to track money owed to you and money you owe.",
                    "Record payments on debts to reduce the remaining balance."
                ]
            ),
            GuideSection(
                title: "Parts Inventory",
                items: [
                    "Use Parts to track part stock, purchase cost, sale price, and available quantity.",
                    "Receive stock when new parts arrive.",
                    "Create part sales with line items so cost and profit stay clear.",
                    "If your dealership does not sell parts, hide the Parts tab from Account."
                ]
            ),
            GuideSection(
                title: "Clients / CRM",
                items: [
                    "Store leads and customers with phone numbers, notes, and status.",
                    "Log interactions and reminders so follow-ups are not lost.",
                    "Link clients to sales and debts when needed.",
                    "Search by name, phone, and notes."
                ]
            ),
            GuideSection(
                title: "Analytics & AI Insights",
                items: [
                    "Open Analytics to review revenue, spend, profit, inventory health, and CRM performance by period.",
                    "Use the period filter to switch between 1D, 1W, 1M, 3M, 6M, and All.",
                    "AI Insights summarizes sales, expenses, and inventory for the selected period.",
                    "AI reports are a Pro feature. If Pro is not active, the button opens the subscription screen.",
                    "The daily AI limit is 15 reports. The card shows how many are used and when the limit resets.",
                    "Generated reports are saved in history. If a report already exists, the app asks before generating a fresh one."
                ]
            ),
            GuideSection(
                title: "Team & Permissions",
                items: [
                    "Owners and admins can invite team members from Account > Team Members.",
                    "A teammate can join with Join Team by Code when an admin shares the code.",
                    "Roles include owner, admin, sales, and viewer.",
                    "Permissions control access to financials, costs, profit, inventory, leads, parts, and deletion."
                ]
            ),
            GuideSection(
                title: "Sync, Offline & Data Health",
                items: [
                    "The app is local-first: changes save on the phone first and sync in the background.",
                    "Use Account > Sync Now when you want to manually push and pull updates.",
                    "Use Account > Data Health to check sync status and possible data issues.",
                    "Owners and admins can run Clean Up Duplicates if duplicate records appear.",
                    "If you are offline, keep working; the app queues changes and syncs when the network is back."
                ]
            ),
            GuideSection(
                title: "Reports, Backups & Notifications",
                items: [
                    "Owners can export data from Account > Backup & Export.",
                    "Email Reports lets eligible users configure monthly report delivery.",
                    "Monthly reports can be previewed before sending or sharing.",
                    "Notifications handle reminders, debt due dates, daily expense reminders, and inventory digest alerts.",
                    "If notifications are disabled, open Account > Notifications to go to iOS settings."
                ]
            ),
            GuideSection(
                title: "Dealer Pro, Referral & Account",
                items: [
                    "Dealer Pro unlocks premium tools, including AI Insights.",
                    "Use the Dealer Pro card in Account to manage your subscription.",
                    "Invite Dealer shares your referral code; you get bonus Pro time when a referred dealer subscribes.",
                    "View referral stats from Account to track invites.",
                    "Change password, contact the developer, read Terms and Privacy Policy, or delete your account from Account."
                ]
            ),
            GuideSection(
                title: "Troubleshooting",
                items: [
                    "If data or photos do not appear, pull to refresh or run Account > Sync Now.",
                    "If duplicate records appear, ask an owner or admin to run Clean Up Duplicates.",
                    "If AI is disabled, check that you are signed in, Pro is active, and the daily limit is not used up.",
                    "If a team member cannot see a feature, check their role and permissions.",
                    "Contact support from Account > Contact Developer."
                ]
            )
        ]
    }

    private var portugueseBrazilSections: [GuideSection] {
        [
            GuideSection(
                title: "Primeiros passos",
                items: [
                    "Entre ou crie uma organização de concessionária.",
                    "Abra Conta > Região e idioma para escolher país, moeda, idioma e formatos.",
                    "Use o seletor de tema em Conta se preferir modo claro ou escuro.",
                    "Adicione seu primeiro veículo em Veículos e depois crie contas financeiras se quiser que os saldos sejam atualizados automaticamente.",
                    "Ative ou desative a aba Peças em Conta, conforme sua concessionária venda peças ou não."
                ]
            ),
            GuideSection(
                title: "Navegação",
                items: [
                    "Abas inferiores: Painel, Despesas, Veículos, Peças, Vendas e Clientes.",
                    "O Painel mostra rapidamente dinheiro, estoque, alertas e atalhos.",
                    "Use a busca nas listas para encontrar veículos, clientes, notas, VINs e registros mais rápido.",
                    "A maioria das telas de detalhe abre ao tocar em uma linha; volte pelo botão do iOS ou deslizando pela borda esquerda."
                ]
            ),
            GuideSection(
                title: "Veículos e fotos",
                items: [
                    "Veículos são os principais registros do seu estoque.",
                    "Os status incluem à venda, reservado, em trânsito, em serviço e vendido.",
                    "Edite um veículo para atualizar preço, quilometragem, dados de compra, notas e status.",
                    "Marcar um veículo como vendido cria um registro de venda.",
                    "Adicione várias fotos, defina uma foto de capa e use Compartilhar para criar um link público do veículo."
                ]
            ),
            GuideSection(
                title: "Custo de permanência",
                items: [
                    "O custo de permanência estima o custo diário de manter um veículo em estoque.",
                    "Configure a taxa anual em Conta > Ajustes de custo de permanência.",
                    "Você pode desativar o custo de permanência se sua concessionária não usa esse cálculo.",
                    "O custo de permanência acumula até a data da venda; depois da venda ele para.",
                    "O lucro da venda inclui o custo de permanência."
                ]
            ),
            GuideSection(
                title: "Despesas e contas financeiras",
                items: [
                    "Registre despesas de veículos, pessoais e de funcionários por categoria.",
                    "Vincule uma despesa a um veículo quando ela pertencer a esse veículo.",
                    "Despesas do veículo afetam o lucro do veículo e a base do custo de permanência.",
                    "Proprietários e administradores podem gerenciar contas de caixa, banco e crédito em Conta > Contas financeiras.",
                    "Ao escolher uma conta para uma venda ou despesa, o saldo dessa conta é atualizado."
                ]
            ),
            GuideSection(
                title: "Vendas e dívidas",
                items: [
                    "Crie uma venda de veículo marcando o veículo como vendido ou registrando uma venda.",
                    "Selecione a conta de recebimento para que o dinheiro entre no saldo correto.",
                    "O lucro inclui preço de venda, preço de compra, despesas, custo de permanência e reembolso de IVA quando usado.",
                    "Use Dívidas para acompanhar valores a receber e valores que você deve.",
                    "Registre pagamentos em dívidas para reduzir o saldo restante."
                ]
            ),
            GuideSection(
                title: "Estoque de peças",
                items: [
                    "Use Peças para controlar estoque, custo de compra, preço de venda e quantidade disponível.",
                    "Receba estoque quando novas peças chegarem.",
                    "Crie vendas de peças com itens de linha para manter custo e lucro claros.",
                    "Se sua concessionária não vende peças, oculte a aba Peças em Conta."
                ]
            ),
            GuideSection(
                title: "Clientes / CRM",
                items: [
                    "Guarde leads e clientes com telefones, notas e status.",
                    "Registre interações e lembretes para não perder follow-ups.",
                    "Vincule clientes a vendas e dívidas quando necessário.",
                    "Busque por nome, telefone e notas."
                ]
            ),
            GuideSection(
                title: "Analytics e AI Insights",
                items: [
                    "Abra Analytics para revisar receita, gastos, lucro, saúde do estoque e desempenho do CRM por período.",
                    "Use o filtro de período para alternar entre 1D, 1S, 1M, 3M, 6M e Tudo.",
                    "AI Insights resume vendas, despesas e estoque para o período selecionado.",
                    "Relatórios de AI são um recurso Pro. Se o Pro não estiver ativo, o botão abre a tela de assinatura.",
                    "O limite diário de AI é de 15 relatórios. O cartão mostra quantos foram usados e quando o limite reinicia.",
                    "Relatórios gerados ficam salvos no histórico. Se já existir um relatório, o app pergunta antes de gerar outro."
                ]
            ),
            GuideSection(
                title: "Equipe e permissões",
                items: [
                    "Proprietários e administradores podem convidar membros da equipe em Conta > Membros da equipe.",
                    "Um colega pode entrar com Entrar na equipe por código quando um administrador compartilhar o código.",
                    "Os papéis incluem proprietário, administrador, vendas e visualizador.",
                    "Permissões controlam acesso a finanças, custos, lucro, estoque, leads, peças e exclusão."
                ]
            ),
            GuideSection(
                title: "Sincronização, offline e saúde dos dados",
                items: [
                    "O app é local-first: as alterações são salvas primeiro no telefone e sincronizam em segundo plano.",
                    "Use Conta > Sincronizar agora quando quiser enviar e receber atualizações manualmente.",
                    "Use Conta > Saúde dos dados para verificar o status de sincronização e possíveis problemas.",
                    "Proprietários e administradores podem executar Limpar duplicatas se registros duplicados aparecerem.",
                    "Se estiver offline, continue trabalhando; o app coloca as alterações na fila e sincroniza quando a rede voltar."
                ]
            ),
            GuideSection(
                title: "Relatórios, backups e notificações",
                items: [
                    "Proprietários podem exportar dados em Conta > Backup e exportação.",
                    "Relatórios por e-mail permite que usuários elegíveis configurem o envio mensal de relatórios.",
                    "Relatórios mensais podem ser pré-visualizados antes de enviar ou compartilhar.",
                    "Notificações cobrem lembretes, vencimento de dívidas, lembrete diário de despesas e alertas de estoque.",
                    "Se as notificações estiverem desativadas, abra Conta > Notificações para ir aos ajustes do iOS."
                ]
            ),
            GuideSection(
                title: "Dealer Pro, indicação e conta",
                items: [
                    "Dealer Pro desbloqueia ferramentas premium, incluindo AI Insights.",
                    "Use o cartão Dealer Pro em Conta para gerenciar sua assinatura.",
                    "Convidar dealer compartilha seu código de indicação; você ganha tempo Pro bônus quando um dealer indicado assina.",
                    "Veja as estatísticas de indicação em Conta para acompanhar convites.",
                    "Altere a senha, fale com o desenvolvedor, leia Termos e Política de Privacidade ou exclua sua conta em Conta."
                ]
            ),
            GuideSection(
                title: "Solução de problemas",
                items: [
                    "Se dados ou fotos não aparecerem, puxe para atualizar ou execute Conta > Sincronizar agora.",
                    "Se registros duplicados aparecerem, peça a um proprietário ou administrador para executar Limpar duplicatas.",
                    "Se a AI estiver desativada, verifique se você entrou, se o Pro está ativo e se o limite diário não acabou.",
                    "Se um membro da equipe não consegue ver um recurso, verifique o papel e as permissões dele.",
                    "Use Conta > Falar com o desenvolvedor para obter suporte."
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
                    "Откройте Account > Region & Language и выберите страну, валюту, язык и форматы.",
                    "Если нужно, переключите светлую или темную тему в Account.",
                    "Добавьте первый автомобиль в Vehicles, затем создайте финансовые счета, если хотите видеть балансы.",
                    "Включите или выключите вкладку Parts в Account, если ваш бизнес работает или не работает с запчастями."
                ]
            ),
            GuideSection(
                title: "Навигация",
                items: [
                    "Нижние вкладки: Dashboard, Expenses, Vehicles, Parts, Sales, Clients.",
                    "Dashboard быстро показывает деньги, склад, предупреждения и важные действия.",
                    "Используйте поиск, чтобы быстрее находить авто, клиентов, заметки, VIN и записи.",
                    "Открывайте детали нажатием на строку; назад можно вернуться кнопкой iOS или свайпом слева."
                ]
            ),
            GuideSection(
                title: "Автомобили и фото",
                items: [
                    "Автомобили — главные записи вашего склада.",
                    "Статусы: в продаже, зарезервирован, в пути, на сервисе, продан.",
                    "В редактировании можно менять цену, пробег, покупку, заметки и статус.",
                    "Когда автомобиль отмечается как проданный, создается запись продажи.",
                    "Добавляйте несколько фото, выбирайте обложку и используйте Share для публичной ссылки на авто."
                ]
            ),
            GuideSection(
                title: "Holding Cost (Burning Inventory)",
                items: [
                    "Holding cost показывает примерную ежедневную стоимость простоя автомобиля на складе.",
                    "Годовую ставку можно настроить в Account > Holding Cost Settings.",
                    "Если функция не нужна, ее можно отключить.",
                    "Начисление идет до даты продажи; после продажи останавливается.",
                    "Прибыль в Sales включает holding cost."
                ]
            ),
            GuideSection(
                title: "Расходы и финансовые счета",
                items: [
                    "Добавляйте расходы по категориям: авто, личные, сотрудники.",
                    "Привязывайте расход к автомобилю, если он относится к конкретной машине.",
                    "Расходы по авто влияют на прибыль автомобиля и базу holding cost.",
                    "Owner и Admin могут управлять cash, bank и credit счетами в Account > Financial Accounts.",
                    "Если выбрать счет в продаже или расходе, баланс этого счета обновится."
                ]
            ),
            GuideSection(
                title: "Продажи и долги",
                items: [
                    "Продажу авто можно создать через статус «продан» или через запись продажи.",
                    "Выберите счет получения денег, чтобы сумма попала в правильный баланс.",
                    "Прибыль учитывает цену продажи, покупку, расходы, holding cost и возврат НДС, если он используется.",
                    "В Debts фиксируйте деньги, которые должны вам, и деньги, которые должны вы.",
                    "Отмечайте оплаты по долгам, чтобы уменьшать остаток."
                ]
            ),
            GuideSection(
                title: "Склад запчастей",
                items: [
                    "В Parts можно вести склад запчастей: количество, себестоимость и цену продажи.",
                    "Приходуйте новые запчасти, когда они поступают.",
                    "Создавайте продажи запчастей с позициями, чтобы видеть себестоимость и прибыль.",
                    "Если запчасти вам не нужны, скройте вкладку Parts в Account."
                ]
            ),
            GuideSection(
                title: "Клиенты / CRM",
                items: [
                    "Храните лидов и клиентов с телефонами, заметками и статусом.",
                    "Добавляйте взаимодействия и напоминания, чтобы не терять follow-up.",
                    "Связывайте клиентов с продажами и долгами, когда это нужно.",
                    "Ищите по имени, телефону и заметкам."
                ]
            ),
            GuideSection(
                title: "Analytics и AI Insights",
                items: [
                    "В Analytics можно смотреть revenue, spend, profit, здоровье склада и CRM по выбранному периоду.",
                    "Фильтр периода переключает 1D, 1W, 1M, 3M, 6M и All.",
                    "AI Insights делает краткий отчет по продажам, расходам и складу за выбранный период.",
                    "AI reports — Pro-функция. Если Pro не активен, кнопка откроет экран подписки.",
                    "Дневной лимит AI — 15 отчетов. Карточка показывает, сколько использовано и когда лимит обновится.",
                    "Отчеты сохраняются в истории. Если отчет уже есть, приложение спросит подтверждение перед новой генерацией."
                ]
            ),
            GuideSection(
                title: "Команда и права",
                items: [
                    "Owner и Admin могут приглашать участников через Account > Team Members.",
                    "Новый участник может войти через Join Team by Code, если админ дал код.",
                    "Основные роли: owner, admin, sales и viewer.",
                    "Права управляют доступом к финансам, себестоимости, прибыли, складу, лидам, запчастям и удалению."
                ]
            ),
            GuideSection(
                title: "Синхронизация и офлайн",
                items: [
                    "Приложение local-first: изменения сначала сохраняются на телефоне, потом синхронизируются в фоне.",
                    "Используйте Account > Sync Now, если хотите вручную отправить и получить обновления.",
                    "Account > Data Health показывает состояние синхронизации и возможные проблемы данных.",
                    "Owner и Admin могут запустить Clean Up Duplicates, если появились дубликаты.",
                    "Если нет интернета, продолжайте работать: изменения встанут в очередь и синхронизируются позже."
                ]
            ),
            GuideSection(
                title: "Отчеты, backup и уведомления",
                items: [
                    "Owner может экспортировать данные через Account > Backup & Export.",
                    "Email Reports позволяет настроить ежемесячную отправку отчетов для пользователей с доступом.",
                    "Monthly reports можно предварительно посмотреть перед отправкой или шарингом.",
                    "Уведомления помогают с напоминаниями, сроками долгов, ежедневным расходом и inventory digest.",
                    "Если уведомления выключены, откройте Account > Notifications и перейдите в настройки iOS."
                ]
            ),
            GuideSection(
                title: "Dealer Pro, referral и аккаунт",
                items: [
                    "Dealer Pro открывает премиум-инструменты, включая AI Insights.",
                    "Подпиской можно управлять через карточку Dealer Pro в Account.",
                    "Invite Dealer делится вашим referral-кодом; вы получаете бонусное Pro-время, когда приглашенный дилер оформит подписку.",
                    "Referral stats в Account показывает статистику приглашений.",
                    "В Account также есть смена пароля, связь с разработчиком, Terms, Privacy Policy и удаление аккаунта."
                ]
            ),
            GuideSection(
                title: "Диагностика",
                items: [
                    "Если данные или фото не появились, потяните список вниз или запустите Account > Sync Now.",
                    "Если появились дубликаты, попросите Owner или Admin запустить Clean Up Duplicates.",
                    "Если AI не работает, проверьте вход в аккаунт, активный Pro и дневной лимит.",
                    "Если участник команды не видит раздел, проверьте его роль и права.",
                    "Поддержка доступна через Account > Contact Developer."
                ]
            )
        ]
    }

    private var uzbekSections: [GuideSection] {
        [
            GuideSection(
                title: "Tez boshlash",
                items: [
                    "Hisobga kiring yoki diler tashkilotini yarating.",
                    "Account > Region & Language bo'limida mamlakat, valyuta, til va formatlarni tanlang.",
                    "Kerak bo'lsa, Account bo'limida light yoki dark mavzuni almashtiring.",
                    "Birinchi avtomobilni Vehicles bo'limidan qo'shing, keyin balanslarni ko'rish uchun moliyaviy hisoblar yarating.",
                    "Dilerligingiz ehtiyot qismlar bilan ishlasa, Account bo'limida Parts tabini yoqing yoki o'chiring."
                ]
            ),
            GuideSection(
                title: "Navigatsiya",
                items: [
                    "Pastki tablar: Boshqaruv paneli, Xarajatlar, Avtomobillar, Qismlar, Sotuvlar, Mijozlar.",
                    "Dashboard pul, ombor, ogohlantirishlar va tezkor amallarni tez ko'rsatadi.",
                    "Qidiruv orqali avtomobil, mijoz, izoh, VIN va yozuvlarni tezroq toping.",
                    "Tafsilotlarni ochish uchun qatorga bosing; orqaga iOS tugmasi yoki chapdan surish bilan qayting."
                ]
            ),
            GuideSection(
                title: "Avtomobillar va rasmlar",
                items: [
                    "Avtomobillar ombordagi asosiy yozuvlardir.",
                    "Holatlar: sotuvda, band qilingan, yo'lda, servisda, sotilgan.",
                    "Tahrirlashda narx, probeg, xarid ma'lumotlari, izoh va holatni yangilash mumkin.",
                    "Avtomobil sotilgan deb belgilanganda sotuv yozuvi yaratiladi.",
                    "Bir nechta rasm qo'shing, muqova tanlang va Share orqali ommaviy havola yarating."
                ]
            ),
            GuideSection(
                title: "Saqlash xarajati",
                items: [
                    "Holding cost avtomobil omborda turgan har kunning taxminiy qiymatini ko'rsatadi.",
                    "Yillik stavkani Account > Holding Cost Settings bo'limida sozlang.",
                    "Bu funksiya kerak bo'lmasa, uni o'chirib qo'yishingiz mumkin.",
                    "Hisoblash sotuv sanasigacha davom etadi; sotuvdan keyin to'xtaydi.",
                    "Sales foydasi holding costni ham hisobga oladi."
                ]
            ),
            GuideSection(
                title: "Xarajatlar va moliyaviy hisoblar",
                items: [
                    "Xarajatlarni kategoriya bo'yicha kiriting: avtomobil, shaxsiy, xodim.",
                    "Xarajat aniq avtomobilga tegishli bo'lsa, uni shu avtomobilga ulang.",
                    "Avtomobil xarajatlari foyda va holding cost bazasiga ta'sir qiladi.",
                    "Owner va Admin Account > Financial Accounts bo'limida cash, bank va credit hisoblarni boshqaradi.",
                    "Sotuv yoki xarajatda hisob tanlansa, o'sha hisob balansi yangilanadi."
                ]
            ),
            GuideSection(
                title: "Sotuvlar va qarzlar",
                items: [
                    "Avtomobil sotuvini statusni sotilgan qilish yoki sotuv yozuvi yaratish orqali kiriting.",
                    "Pul to'g'ri balansga tushishi uchun qabul qiluvchi hisobni tanlang.",
                    "Foyda sotuv narxi, xarid narxi, xarajatlar, holding cost va QQS qaytimini hisobga oladi.",
                    "Debts bo'limida sizga qarz bo'lgan va siz qarzdor bo'lgan summalarni kuzating.",
                    "Qarz bo'yicha to'lovlarni kiriting, shunda qolgan balans kamayadi."
                ]
            ),
            GuideSection(
                title: "Ehtiyot qismlar ombori",
                items: [
                    "Parts bo'limida qism nomi, miqdori, tannarxi va sotuv narxini kuzating.",
                    "Yangi qismlar kelganda ularni omborga qabul qiling.",
                    "Qismlar sotuvini pozitsiyalar bilan yarating, shunda tannarx va foyda aniq bo'ladi.",
                    "Agar qismlar kerak bo'lmasa, Account bo'limida Parts tabini yashiring."
                ]
            ),
            GuideSection(
                title: "Mijozlar / CRM",
                items: [
                    "Lid va mijozlarni telefon, izoh va status bilan saqlang.",
                    "Follow-up yo'qolmasligi uchun muloqotlar va eslatmalar qo'shing.",
                    "Kerak bo'lsa, mijozlarni sotuvlar va qarzlarga ulang.",
                    "Ism, telefon va izoh bo'yicha qidiring."
                ]
            ),
            GuideSection(
                title: "Analytics va AI Insights",
                items: [
                    "Analytics bo'limida tanlangan davr bo'yicha revenue, spend, profit, ombor holati va CRM ko'rsatkichlarini ko'ring.",
                    "Davr filtri 1D, 1W, 1M, 3M, 6M va All oralig'ini almashtiradi.",
                    "AI Insights tanlangan davr uchun sotuv, xarajat va omborni qisqa hisobot qiladi.",
                    "AI reports Pro funksiyasi. Pro aktiv bo'lmasa, tugma obuna ekranini ochadi.",
                    "Kunlik AI limiti 15 ta hisobot. Kartada nechta ishlatilgani va qachon yangilanishi ko'rsatiladi.",
                    "Hisobotlar tarixda saqlanadi. Hisobot bor bo'lsa, yangi generatsiyadan oldin ilova tasdiq so'raydi."
                ]
            ),
            GuideSection(
                title: "Jamoa va ruxsatlar",
                items: [
                    "Owner va Admin Account > Team Members orqali jamoa a'zolarini taklif qiladi.",
                    "Yangi a'zo admin bergan kod bilan Join Team by Code orqali qo'shiladi.",
                    "Asosiy rollar: owner, admin, sales va viewer.",
                    "Ruxsatlar moliya, tannarx, foyda, ombor, lidlar, qismlar va o'chirishga kirishni boshqaradi."
                ]
            ),
            GuideSection(
                title: "Sinxronlash va oflayn",
                items: [
                    "Ilova local-first: o'zgarishlar avval telefonda saqlanadi, keyin fonda sinxronlanadi.",
                    "Yangilanishlarni qo'lda yuborish va olish uchun Account > Sync Now dan foydalaning.",
                    "Account > Data Health sinxronlash holati va mumkin bo'lgan muammolarni ko'rsatadi.",
                    "Dublikatlar paydo bo'lsa, Owner yoki Admin Clean Up Duplicates ishga tushirishi mumkin.",
                    "Internet bo'lmasa ham ishlashda davom eting; o'zgarishlar navbatga yoziladi va keyin sinxronlanadi."
                ]
            ),
            GuideSection(
                title: "Hisobotlar, backup va bildirishnomalar",
                items: [
                    "Owner Account > Backup & Export orqali ma'lumotlarni eksport qiladi.",
                    "Email Reports ruxsati bor foydalanuvchilarga oylik hisobot yuborishni sozlashga yordam beradi.",
                    "Monthly reports yuborish yoki ulashishdan oldin ko'rib chiqilishi mumkin.",
                    "Bildirishnomalar eslatmalar, qarz muddatlari, kundalik xarajat eslatmasi va inventory digest uchun ishlaydi.",
                    "Bildirishnomalar o'chirilgan bo'lsa, Account > Notifications orqali iOS sozlamalariga o'ting."
                ]
            ),
            GuideSection(
                title: "Dealer Pro, referral va akkaunt",
                items: [
                    "Dealer Pro premium vositalarni, jumladan AI Insightsni ochadi.",
                    "Obunani Account ichidagi Dealer Pro kartasi orqali boshqaring.",
                    "Invite Dealer referral kodingizni ulashadi; taklif qilingan diler obuna bo'lsa, bonus Pro vaqti olasiz.",
                    "Referral stats takliflar statistikasini ko'rsatadi.",
                    "Account bo'limida parolni o'zgartirish, dasturchi bilan bog'lanish, Terms, Privacy Policy va akkauntni o'chirish mavjud."
                ]
            ),
            GuideSection(
                title: "Nosozliklarni bartaraf etish",
                items: [
                    "Ma'lumot yoki rasm ko'rinmasa, ro'yxatni pastga torting yoki Account > Sync Now ni ishga tushiring.",
                    "Dublikatlar ko'rinsa, Owner yoki Admin Clean Up Duplicates ishga tushirsin.",
                    "AI ishlamasa, hisobga kirilganini, Pro aktivligini va kunlik limit tugamaganini tekshiring.",
                    "Jamoa a'zosi biror bo'limni ko'rmasa, uning roli va ruxsatlarini tekshiring.",
                    "Yordam uchun Account > Contact Developer dan foydalaning."
                ]
            )
        ]
    }
}

private struct GuideSectionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let section: GuideSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .font(.title3.weight(.bold))
                .foregroundColor(ColorTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(ColorTheme.primary.opacity(0.65))
                            .frame(width: 6, height: 6)
                            .padding(.top, 8)

                        Text(item)
                            .font(.body)
                            .lineSpacing(3)
                            .foregroundColor(ColorTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.04), radius: 10, x: 0, y: 5)
    }
}

private struct GuideSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}
