
import json
import os

file_path = "Ezcar24Business/Localizable.xcstrings"

new_translations = {
    "all_filter": { "value": "All", "ru": "Все" },
    "revenue": { "value": "Revenue", "ru": "Выручка" },
    "cost": { "value": "Cost", "ru": "Расходы" },
    "net_profit": { "value": "Net Profit", "ru": "Чистая прибыль" },
    "search_vehicle_or_buyer": { "value": "Search vehicle or buyer...", "ru": "Поиск авто или покупателя..." },
    "no_expenses_period": { "value": "No expenses for this period", "ru": "Нет расходов за этот период" },
    "spending_breakdown": { "value": "Spending Breakdown", "ru": "Структура расходов" },
    "sales_history": { "value": "Sales History", "ru": "История продаж" },
    "sales": { "value": "Sales", "ru": "Продажи" },
    "debts": { "value": "Debts", "ru": "Долги" },
    "search_name_or_notes": { "value": "Search name or notes...", "ru": "Поиск по имени или заметкам..." },
    "no_sales_yet": { "value": "No sales yet", "ru": "Продаж пока нет" },
    "record_first_sale": { "value": "Record your first sale to see it here.", "ru": "Запишите свою первую продажу, чтобы увидеть ее здесь." },
    "search": { "value": "Search", "ru": "Поиск" },
    "done": { "value": "Done", "ru": "Готово" }
}

def update_xcstrings():
    if not os.path.exists(file_path):
        print(f"Error: File not found at {file_path}")
        return

    with open(file_path, 'r') as f:
        data = json.load(f)

    changed = False
    for key, trans in new_translations.items():
        if key not in data["strings"]:
            print(f"Adding new key: {key}")
            data["strings"][key] = {
                "extractionState": "manual",
                "localizations": {
                    "en": { "stringUnit": { "state": "translated", "value": trans["value"] } },
                    "ru": { "stringUnit": { "state": "translated", "value": trans["ru"] } }
                }
            }
            changed = True
        else:
            # Check if Russian translation is missing or needs update
            # (Basic check, blindly updating if missing)
            if "localizations" not in data["strings"][key]:
                data["strings"][key]["localizations"] = {}
            
            if "ru" not in data["strings"][key]["localizations"]:
                print(f"Adding Russian translation for existing key: {key}")
                data["strings"][key]["localizations"]["ru"] = {
                    "stringUnit": { "state": "translated", "value": trans["ru"] }
                }
                changed = True
            elif data["strings"][key]["localizations"]["ru"]["stringUnit"]["value"] != trans["ru"]:
                 print(f"Updating Russian translation for key: {key}")
                 data["strings"][key]["localizations"]["ru"]["stringUnit"]["value"] = trans["ru"]
                 changed = True

    if changed:
        with open(file_path, 'w') as f:
            json.dump(data, f, indent=2, sort_keys=True)
        print("Updated Localizable.xcstrings successfully.")
    else:
        print("No changes needed in Localizable.xcstrings.")

if __name__ == "__main__":
    update_xcstrings()
