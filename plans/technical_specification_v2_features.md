# CarDealerTracker v2.0 Technical Specification
## Holding Cost, CRM/Leads Funnel & Inventory Turnover Metrics

---

## Executive Summary

This document provides comprehensive technical specifications for three critical features to enhance CarDealerTracker's financial intelligence and sales management capabilities:

1. **Holding Cost (Стоимость владения)** - Capital opportunity cost tracking
2. **CRM/Leads Funnel (Воронка продаж)** - Lead management and conversion tracking
3. **Inventory Turnover Metrics (Оборачиваемость)** - Performance analytics and aging alerts

---

## Current Architecture Overview

### Data Models (Existing)

**Android (Room/Kotlin):**
- `Vehicle`: id, vin, make, model, year, purchasePrice, purchaseDate, status, salePrice, saleDate
- `Expense`: id, amount, date, category, vehicleId
- `Client`: id, name, phone, status, vehicleId
- `ClientInteraction`: id, title, detail, occurredAt, stage, clientId

**iOS (CoreData/Swift):**
- `Vehicle`: Same fields as Android
- `Expense`: Same fields as Android
- `Client`: Same fields as Android
- `ClientInteraction`: Same fields + `InteractionStage` enum (outreach, qualification, negotiation, offer, testDrive, closedWon, closedLost, followUp, update)

**Supabase Backend:**
- Tables: vehicles, expenses, clients, client_interactions, sales, users, financial_accounts
- Multi-tenant via `dealer_id` column
- Soft delete pattern with `deleted_at` column

---

## Feature 1: Holding Cost (Стоимость владения)

### 1.1 Problem Statement
Current profit calculation: `Sale Price - (Purchase Price + Expenses)` misses opportunity cost. A car sitting for 30 days ties up capital that could generate returns elsewhere.

### 1.2 Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| HC-1 | Calculate daily holding cost based on capital tied up | P0 |
| HC-2 | Formula: `Days in Inventory × Daily Rate × (Purchase Price + Improvement Expenses)` | P0 |
| HC-3 | Configurable daily rate (default: 15% annual → 0.041% daily) | P0 |
| HC-4 | Classify expenses: holding_cost vs improvement vs operational | P0 |
| HC-5 | Show holding cost in vehicle detail and profit calculations | P0 |
| HC-6 | Alert when holding cost exceeds threshold | P1 |

### 1.3 Entity/Model Changes

#### Android (Kotlin/Room)

```kotlin
// New enum for expense classification
enum class ExpenseCategoryType {
    HOLDING_COST,      // Costs incurred while holding (storage, insurance)
    IMPROVEMENT,       // Adds value to vehicle (repairs, detailing)
    OPERATIONAL,       // General business expenses
    MARKETING          // Advertising, listing fees
}

// Updated Expense entity
@Entity(tableName = "expenses")
data class Expense(
    @PrimaryKey val id: UUID,
    val amount: BigDecimal = BigDecimal.ZERO,
    val date: Date,
    val expenseDescription: String?,
    val category: String,                    // Keep for backward compatibility
    val categoryType: String = "operational", // New: expense_category_type
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val vehicleId: UUID?,
    val userId: UUID?,
    val accountId: UUID?
)

// New entity: HoldingCostSettings
@Entity(tableName = "holding_cost_settings")
data class HoldingCostSettings(
    @PrimaryKey val id: UUID = UUID.fromString("00000000-0000-0000-0000-000000000001"),
    val annualRatePercent: BigDecimal = BigDecimal("15.0"),
    val dailyRatePercent: BigDecimal = BigDecimal("0.041096"), // 15/365
    val alertThresholdDays: Int = 60,
    val alertThresholdCostPercent: BigDecimal = BigDecimal("10.0"), // Alert when holding cost > 10% of purchase price
    val updatedAt: Date? = null
)

// New entity: VehicleHoldingCost (computed/cache)
@Entity(tableName = "vehicle_holding_costs")
data class VehicleHoldingCost(
    @PrimaryKey val vehicleId: UUID,
    val daysInInventory: Int,
    val dailyRate: BigDecimal,
    val capitalTiedUp: BigDecimal,           // purchasePrice + improvementExpenses
    val totalHoldingCost: BigDecimal,
    val lastCalculatedAt: Date,
    val shouldAlert: Boolean = false
)
```

#### iOS (CoreData/Swift)

```swift
// New enum
enum ExpenseCategoryType: String, CaseIterable, Identifiable {
    case holdingCost = "holding_cost"
    case improvement = "improvement"
    case operational = "operational"
    case marketing = "marketing"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .holdingCost: return "Holding Cost"
        case .improvement: return "Improvement"
        case .operational: return "Operational"
        case .marketing: return "Marketing"
        }
    }
}

// Updated Expense entity (CoreData)
// Add attributes:
// - categoryType: String (default: "operational")

// New entity: HoldingCostSettings
// Attributes:
// - id: UUID
// - annualRatePercent: Decimal (default: 15.0)
// - dailyRatePercent: Decimal (default: 0.041096)
// - alertThresholdDays: Int32 (default: 60)
// - alertThresholdCostPercent: Decimal (default: 10.0)
// - updatedAt: Date

// New entity: VehicleHoldingCost
// Attributes:
// - vehicleId: UUID
// - daysInInventory: Int32
// - dailyRate: Decimal
// - capitalTiedUp: Decimal
// - totalHoldingCost: Decimal
// - lastCalculatedAt: Date
// - shouldAlert: Bool
```

### 1.4 Database Schema (Supabase)

```sql
-- Add category_type to expenses table
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS category_type TEXT DEFAULT 'operational';

-- Create index for category type filtering
CREATE INDEX IF NOT EXISTS idx_expenses_category_type ON expenses(category_type) WHERE deleted_at IS NULL;

-- Create holding_cost_settings table
CREATE TABLE IF NOT EXISTS holding_cost_settings (
    id UUID PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::UUID,
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    annual_rate_percent DECIMAL(5,2) NOT NULL DEFAULT 15.0,
    daily_rate_percent DECIMAL(10,6) NOT NULL DEFAULT 0.041096, -- 15/365
    alert_threshold_days INTEGER NOT NULL DEFAULT 60,
    alert_threshold_cost_percent DECIMAL(5,2) NOT NULL DEFAULT 10.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(dealer_id)
);

-- RLS for holding_cost_settings
ALTER TABLE holding_cost_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Dealers can manage their holding cost settings"
    ON holding_cost_settings
    USING (dealer_id IN (
        SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()
    ));

-- Create vehicle_holding_costs table (computed values)
CREATE TABLE IF NOT EXISTS vehicle_holding_costs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    days_in_inventory INTEGER NOT NULL DEFAULT 0,
    daily_rate DECIMAL(10,6) NOT NULL,
    capital_tied_up DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_holding_cost DECIMAL(15,2) NOT NULL DEFAULT 0,
    should_alert BOOLEAN DEFAULT FALSE,
    last_calculated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(dealer_id, vehicle_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_vehicle_holding_costs_vehicle ON vehicle_holding_costs(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_holding_costs_alert ON vehicle_holding_costs(should_alert) WHERE should_alert = TRUE;

-- RLS
ALTER TABLE vehicle_holding_costs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Dealers can view their vehicle holding costs"
    ON vehicle_holding_costs
    USING (dealer_id IN (
        SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()
    ));
```

### 1.5 API Design

#### New RPC Functions

```sql
-- Calculate holding cost for a single vehicle
CREATE OR REPLACE FUNCTION calculate_vehicle_holding_cost(p_vehicle_id UUID)
RETURNS TABLE (
    days_in_inventory INTEGER,
    daily_rate DECIMAL,
    capital_tied_up DECIMAL,
    total_holding_cost DECIMAL,
    should_alert BOOLEAN
) AS $$
DECLARE
    v_settings RECORD;
    v_vehicle RECORD;
    v_improvement_expenses DECIMAL;
    v_days INTEGER;
    v_capital DECIMAL;
    v_holding_cost DECIMAL;
BEGIN
    -- Get settings
    SELECT * INTO v_settings 
    FROM holding_cost_settings 
    WHERE dealer_id = (SELECT dealer_id FROM vehicles WHERE id = p_vehicle_id)
    AND deleted_at IS NULL
    LIMIT 1;
    
    -- Default settings if none exist
    IF v_settings IS NULL THEN
        v_settings.annual_rate_percent := 15.0;
        v_settings.daily_rate_percent := 0.041096;
        v_settings.alert_threshold_days := 60;
        v_settings.alert_threshold_cost_percent := 10.0;
    END IF;
    
    -- Get vehicle
    SELECT * INTO v_vehicle 
    FROM vehicles 
    WHERE id = p_vehicle_id AND deleted_at IS NULL;
    
    IF v_vehicle IS NULL THEN
        RETURN;
    END IF;
    
    -- Calculate improvement expenses
    SELECT COALESCE(SUM(amount), 0) INTO v_improvement_expenses
    FROM expenses
    WHERE vehicle_id = p_vehicle_id 
    AND category_type = 'improvement'
    AND deleted_at IS NULL;
    
    -- Calculate days in inventory
    IF v_vehicle.status = 'sold' AND v_vehicle.sale_date IS NOT NULL THEN
        v_days := v_vehicle.sale_date::date - v_vehicle.purchase_date::date;
    ELSE
        v_days := CURRENT_DATE - v_vehicle.purchase_date::date;
    END IF;
    
    v_days := GREATEST(v_days, 0);
    
    -- Calculate capital tied up
    v_capital := COALESCE(v_vehicle.purchase_price, 0) + v_improvement_expenses;
    
    -- Calculate holding cost
    v_holding_cost := ROUND(v_days * (v_settings.daily_rate_percent / 100) * v_capital, 2);
    
    -- Determine if should alert
    RETURN QUERY SELECT 
        v_days,
        v_settings.daily_rate_percent,
        v_capital,
        v_holding_cost,
        (v_days >= v_settings.alert_threshold_days OR 
         (v_capital > 0 AND (v_holding_cost / v_capital * 100) >= v_settings.alert_threshold_cost_percent));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Batch recalculate all holding costs for a dealer
CREATE OR REPLACE FUNCTION recalculate_all_holding_costs(p_dealer_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_vehicle RECORD;
    v_result RECORD;
BEGIN
    FOR v_vehicle IN 
        SELECT id FROM vehicles 
        WHERE dealer_id = p_dealer_id 
        AND deleted_at IS NULL
    LOOP
        SELECT * INTO v_result FROM calculate_vehicle_holding_cost(v_vehicle.id);
        
        INSERT INTO vehicle_holding_costs (
            dealer_id, vehicle_id, days_in_inventory, daily_rate,
            capital_tied_up, total_holding_cost, should_alert, last_calculated_at
        ) VALUES (
            p_dealer_id, v_vehicle.id, v_result.days_in_inventory, v_result.daily_rate,
            v_result.capital_tied_up, v_result.total_holding_cost, v_result.should_alert, NOW()
        )
        ON CONFLICT (dealer_id, vehicle_id) DO UPDATE SET
            days_in_inventory = EXCLUDED.days_in_inventory,
            daily_rate = EXCLUDED.daily_rate,
            capital_tied_up = EXCLUDED.capital_tied_up,
            total_holding_cost = EXCLUDED.total_holding_cost,
            should_alert = EXCLUDED.should_alert,
            last_calculated_at = EXCLUDED.last_calculated_at,
            updated_at = NOW();
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get vehicles with high holding costs
CREATE OR REPLACE FUNCTION get_vehicles_with_high_holding_cost(
    p_dealer_id UUID,
    p_threshold_days INTEGER DEFAULT 60
)
RETURNS TABLE (
    vehicle_id UUID,
    vin TEXT,
    make TEXT,
    model TEXT,
    days_in_inventory INTEGER,
    total_holding_cost DECIMAL,
    capital_tied_up DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id,
        v.vin,
        v.make,
        v.model,
        vhc.days_in_inventory,
        vhc.total_holding_cost,
        vhc.capital_tied_up
    FROM vehicle_holding_costs vhc
    JOIN vehicles v ON vhc.vehicle_id = v.id
    WHERE vhc.dealer_id = p_dealer_id
    AND vhc.should_alert = TRUE
    AND v.deleted_at IS NULL
    AND vhc.deleted_at IS NULL
    ORDER BY vhc.total_holding_cost DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 1.6 Calculation Logic

```kotlin
// HoldingCostCalculator.kt
@Singleton
class HoldingCostCalculator @Inject constructor(
    private val settingsDao: HoldingCostSettingsDao,
    private val expenseDao: ExpenseDao
) {
    
    fun calculateHoldingCost(
        vehicle: Vehicle,
        settings: HoldingCostSettings? = null
    ): HoldingCostResult {
        val effectiveSettings = settings ?: HoldingCostSettings() // defaults
        
        // Calculate days in inventory
        val daysInInventory = calculateDaysInInventory(vehicle)
        
        // Get improvement expenses
        val improvementExpenses = runBlocking {
            expenseDao.getImprovementExpensesForVehicle(vehicle.id)
        }.sumOf { it.amount }
        
        // Capital tied up
        val capitalTiedUp = vehicle.purchasePrice.add(improvementExpenses)
        
        // Calculate holding cost
        val dailyRateDecimal = effectiveSettings.dailyRatePercent
            .divide(BigDecimal("100"))
        
        val totalHoldingCost = BigDecimal(daysInInventory)
            .multiply(dailyRateDecimal)
            .multiply(capitalTiedUp)
            .setScale(2, RoundingMode.HALF_UP)
        
        // Check alert conditions
        val shouldAlert = daysInInventory >= effectiveSettings.alertThresholdDays ||
            (capitalTiedUp > BigDecimal.ZERO && 
             totalHoldingCost.divide(capitalTiedUp, 4, RoundingMode.HALF_UP)
                 .multiply(BigDecimal("100")) >= effectiveSettings.alertThresholdCostPercent)
        
        return HoldingCostResult(
            vehicleId = vehicle.id,
            daysInInventory = daysInInventory,
            dailyRate = effectiveSettings.dailyRatePercent,
            capitalTiedUp = capitalTiedUp,
            totalHoldingCost = totalHoldingCost,
            shouldAlert = shouldAlert
        )
    }
    
    private fun calculateDaysInInventory(vehicle: Vehicle): Int {
        val endDate = if (vehicle.status == "sold" && vehicle.saleDate != null) {
            vehicle.saleDate
        } else {
            Date()
        }
        
        val diffMillis = endDate.time - vehicle.purchaseDate.time
        return max(0, (diffMillis / (1000 * 60 * 60 * 24)).toInt())
    }
}

data class HoldingCostResult(
    val vehicleId: UUID,
    val daysInInventory: Int,
    val dailyRate: BigDecimal,
    val capitalTiedUp: BigDecimal,
    val totalHoldingCost: BigDecimal,
    val shouldAlert: Boolean
)
```

### 1.7 UI Components

```kotlin
// HoldingCostCard.kt
@Composable
fun HoldingCostCard(
    holdingCost: HoldingCostResult,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (holdingCost.shouldAlert) Color(0xFFFFF3E0) else Color.White
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Holding Cost",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                if (holdingCost.shouldAlert) {
                    Icon(
                        imageVector = Icons.Default.Warning,
                        contentDescription = "Alert",
                        tint = Color(0xFFFF9800)
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            
            // Days in inventory
            InfoRow(label = "Days in Inventory", value = "${holdingCost.daysInInventory} days")
            
            // Daily rate
            InfoRow(
                label = "Daily Rate", 
                value = "${holdingCost.dailyRate}%"
            )
            
            // Capital tied up
            InfoRow(
                label = "Capital Tied Up",
                value = formatCurrency(holdingCost.capitalTiedUp)
            )
            
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            
            // Total holding cost
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    "Total Holding Cost",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    formatCurrency(holdingCost.totalHoldingCost),
                    style = MaterialTheme.typography.titleSmall,
                    color = if (holdingCost.shouldAlert) Color(0xFFFF9800) else Color.Unspecified,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

// Updated Profit Calculation Display
@Composable
fun ProfitCalculationCard(
    vehicle: Vehicle,
    totalExpenses: BigDecimal,
    holdingCost: BigDecimal,
    salePrice: BigDecimal?
) {
    val totalCost = vehicle.purchasePrice.add(totalExpenses).add(holdingCost)
    val profit = salePrice?.subtract(totalCost)
    
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Profit Calculation", style = MaterialTheme.typography.titleMedium)
            
            Spacer(modifier = Modifier.height(8.dp))
            
            CalculationRow("Purchase Price", vehicle.purchasePrice)
            CalculationRow("Expenses", totalExpenses)
            CalculationRow("Holding Cost", holdingCost, isHighlight = true)
            
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            
            CalculationRow("Total Cost", totalCost, isBold = true)
            
            if (salePrice != null) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                CalculationRow("Sale Price", salePrice, isBold = true)
                CalculationRow(
                    "Net Profit", 
                    profit ?: BigDecimal.ZERO,
                    isBold = true,
                    color = if ((profit ?: BigDecimal.ZERO) >= BigDecimal.ZERO) 
                        Color(0xFF4CAF50) else Color(0xFFF44336)
                )
            }
        }
    }
}
```

### 1.8 Sync Strategy

| Entity | Sync Priority | Conflict Resolution |
|--------|---------------|---------------------|
| `expenses.category_type` | High | Server wins |
| `holding_cost_settings` | Medium | Last write wins |
| `vehicle_holding_costs` | Low (computed) | Recalculate on client |

**Sync Flow:**
1. Client syncs `expenses` with new `category_type` field
2. Client fetches `holding_cost_settings` for dealer
3. Client calculates `vehicle_holding_costs` locally (not synced as computed)
4. Server RPC `recalculate_all_holding_costs` runs nightly via cron

### 1.9 Backward Compatibility

```kotlin
// Migration: Default all existing expenses to 'operational'
// Room Migration
val MIGRATION_X_TO_Y = object : Migration(X, Y) {
    override fun migrate(db: SupportSQLiteDatabase) {
        // Add category_type column with default
        db.execSQL("ALTER TABLE expenses ADD COLUMN category_type TEXT DEFAULT 'operational'")
        
        // Create holding_cost_settings table
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS holding_cost_settings (
                id TEXT PRIMARY KEY NOT NULL,
                annual_rate_percent REAL NOT NULL DEFAULT 15.0,
                daily_rate_percent REAL NOT NULL DEFAULT 0.041096,
                alert_threshold_days INTEGER NOT NULL DEFAULT 60,
                alert_threshold_cost_percent REAL NOT NULL DEFAULT 10.0,
                updated_at INTEGER,
                deleted_at INTEGER
            )
        """)
        
        // Create vehicle_holding_costs table
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS vehicle_holding_costs (
                vehicle_id TEXT PRIMARY KEY NOT NULL,
                days_in_inventory INTEGER NOT NULL DEFAULT 0,
                daily_rate REAL NOT NULL,
                capital_tied_up REAL NOT NULL DEFAULT 0,
                total_holding_cost REAL NOT NULL DEFAULT 0,
                should_alert INTEGER DEFAULT 0,
                last_calculated_at INTEGER,
                deleted_at INTEGER
            )
        """)
    }
}
```

---

## Feature 2: CRM/Leads Funnel (Воронка продаж)

### 2.1 Problem Statement
Basic client table exists but lacks proper lead tracking. No visibility into:
- Calls made today
- Funnel stage per client
- Lead source/channel effectiveness

### 2.2 Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| LF-1 | Lead stages: new → contacted → qualified → negotiation → offer → test_drive → closed_won/closed_lost | P0 |
| LF-2 | Track lead source/channel (Facebook, Dubizzle, Instagram, Referral, Walk-in, Phone, Other) | P0 |
| LF-3 | Track interactions per lead (calls, meetings, messages) | P0 |
| LF-4 | Funnel metrics: conversion rates, time per stage, pipeline value | P1 |
| LF-5 | Daily activity tracking (calls made, leads added) | P1 |
| LF-6 | Lead scoring based on interactions | P2 |

### 2.3 Entity/Model Changes

#### Android (Kotlin/Room)

```kotlin
// LeadStage enum (extends existing interaction stages)
enum class LeadStage {
    NEW,
    CONTACTED,
    QUALIFIED,
    NEGOTIATION,
    OFFER,
    TEST_DRIVE,
    CLOSED_WON,
    CLOSED_LOST;
    
    fun isClosed(): Boolean = this == CLOSED_WON || this == CLOSED_LOST
    fun isActive(): Boolean = !isClosed()
}

// LeadSource enum
enum class LeadSource {
    FACEBOOK,
    DUBIZZLE,
    INSTAGRAM,
    REFERRAL,
    WALK_IN,
    PHONE,
    WEBSITE,
    OTHER;
    
    fun displayName(): String = when (this) {
        FACEBOOK -> "Facebook"
        DUBIZZLE -> "Dubizzle"
        INSTAGRAM -> "Instagram"
        REFERRAL -> "Referral"
        WALK_IN -> "Walk-in"
        PHONE -> "Phone"
        WEBSITE -> "Website"
        OTHER -> "Other"
    }
}

// InteractionType enum
enum class InteractionType {
    CALL,
    MEETING,
    MESSAGE,
    EMAIL,
    TEST_DRIVE,
    OFFER_MADE,
    NOTE
}

// Updated Client entity - extend for lead management
@Entity(tableName = "clients")
data class Client(
    @PrimaryKey val id: UUID,
    val name: String,
    val phone: String?,
    val email: String?,
    val notes: String?,
    val requestDetails: String?,
    val preferredDate: Date?,
    
    // Existing - keep for backward compatibility
    val status: String? = "new",
    
    // New lead management fields
    val leadStage: String = "new",           // LeadStage enum value
    val leadSource: String? = null,          // LeadSource enum value
    val leadSourceDetail: String? = null,    // e.g., "Facebook Ad Campaign Q1"
    val assignedToUserId: UUID? = null,      // Salesperson assignment
    val estimatedValue: BigDecimal? = null,  // Potential deal value
    val priority: Int = 0,                   // 0-5 priority score
    val lastContactDate: Date? = null,       // Last interaction date
    val nextFollowUpDate: Date? = null,      // Scheduled follow-up
    val leadScore: Int = 0,                  // Computed score (0-100)
    
    // Existing
    val createdAt: Date,
    val updatedAt: Date?,
    val deletedAt: Date? = null,
    val vehicleId: UUID?
)

// Updated ClientInteraction entity
@Entity(tableName = "client_interactions")
data class ClientInteraction(
    @PrimaryKey val id: UUID,
    val title: String?,
    val detail: String?,
    val occurredAt: Date,
    
    // Existing - keep for compatibility
    val stage: String? = "update",
    val value: BigDecimal?,
    
    // New fields
    val interactionType: String = "note",    // InteractionType enum
    val outcome: String? = null,             // e.g., "answered", "no_answer", "scheduled"
    val durationMinutes: Int? = null,        // For calls/meetings
    val leadStageBefore: String? = null,     // Stage before this interaction
    val leadStageAfter: String? = null,      // Stage after this interaction
    val isFollowUp: Boolean = false,         // Whether this was a scheduled follow-up
    
    val clientId: UUID?
)

// New entity: LeadActivity (for daily tracking)
@Entity(tableName = "lead_activities")
data class LeadActivity(
    @PrimaryKey val id: UUID,
    val userId: UUID,                        // Who performed the activity
    val activityType: String,                // "call", "meeting", "lead_added", "stage_change"
    val leadId: UUID? = null,                // Related lead (if applicable)
    val count: Int = 1,                      // Number of activities
    val activityDate: Date,                  // Date of activity (not timestamp)
    val createdAt: Date = Date()
)

// New entity: FunnelMetrics (computed/cache)
@Entity(tableName = "funnel_metrics")
data class FunnelMetrics(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val dealerId: UUID,
    val stage: String,
    val leadCount: Int,
    val totalValue: BigDecimal?,
    val avgDaysInStage: Double,
    val conversionRate: Double,              // % converting to next stage
    val calculatedAt: Date = Date()
)
```

#### iOS (CoreData/Swift)

```swift
// LeadStage enum (extends existing InteractionStage)
enum LeadStage: String, CaseIterable, Identifiable {
    case new = "new"
    case contacted = "contacted"
    case qualified = "qualified"
    case negotiation = "negotiation"
    case offer = "offer"
    case testDrive = "test_drive"
    case closedWon = "closed_won"
    case closedLost = "closed_lost"
    
    var id: String { rawValue }
    
    var isClosed: Bool {
        self == .closedWon || self == .closedLost
    }
    
    var isActive: Bool { !isClosed }
    
    var displayOrder: Int {
        switch self {
        case .new: return 0
        case .contacted: return 1
        case .qualified: return 2
        case .negotiation: return 3
        case .offer: return 4
        case .testDrive: return 5
        case .closedWon: return 6
        case .closedLost: return 7
        }
    }
}

// LeadSource enum
enum LeadSource: String, CaseIterable, Identifiable {
    case facebook = "facebook"
    case dubizzle = "dubizzle"
    case instagram = "instagram"
    case referral = "referral"
    case walkIn = "walk_in"
    case phone = "phone"
    case website = "website"
    case other = "other"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .facebook: return "Facebook"
        case .dubizzle: return "Dubizzle"
        case .instagram: return "Instagram"
        case .referral: return "Referral"
        case .walkIn: return "Walk-in"
        case .phone: return "Phone"
        case .website: return "Website"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .facebook: return "f.square.fill"
        case .dubizzle: return "d.square.fill"
        case .instagram: return "camera.fill"
        case .referral: return "person.2.fill"
        case .walkIn: return "door.left.hand.open"
        case .phone: return "phone.fill"
        case .website: return "globe"
        case .other: return "questionmark.circle.fill"
        }
    }
}

// Updated Client entity (CoreData)
// Add attributes:
// - leadStage: String (default: "new")
// - leadSource: String?
// - leadSourceDetail: String?
// - assignedToUserId: UUID?
// - estimatedValue: Decimal?
// - priority: Int32 (default: 0)
// - lastContactDate: Date?
// - nextFollowUpDate: Date?
// - leadScore: Int32 (default: 0)

// Updated ClientInteraction entity
// Add attributes:
// - interactionType: String (default: "note")
// - outcome: String?
// - durationMinutes: Int32?
// - leadStageBefore: String?
// - leadStageAfter: String?
// - isFollowUp: Bool (default: false)
```

### 2.4 Database Schema (Supabase)

```sql
-- Add lead management columns to clients table
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_stage TEXT DEFAULT 'new';
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_source TEXT;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_source_detail TEXT;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS assigned_to_user_id UUID REFERENCES auth.users(id);
ALTER TABLE clients ADD COLUMN IF NOT EXISTS estimated_value DECIMAL(15,2);
ALTER TABLE clients ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 0;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS last_contact_date DATE;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS next_follow_up_date DATE;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_score INTEGER DEFAULT 0;

-- Add indexes for lead queries
CREATE INDEX IF NOT EXISTS idx_clients_lead_stage ON clients(lead_stage) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_clients_lead_source ON clients(lead_source) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_clients_assigned ON clients(assigned_to_user_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_clients_next_followup ON clients(next_follow_up_date) 
    WHERE deleted_at IS NULL AND next_follow_up_date IS NOT NULL;

-- Add interaction tracking columns
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS interaction_type TEXT DEFAULT 'note';
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS outcome TEXT;
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS duration_minutes INTEGER;
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS lead_stage_before TEXT;
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS lead_stage_after TEXT;
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS is_follow_up BOOLEAN DEFAULT FALSE;

-- Create lead_activities table
CREATE TABLE IF NOT EXISTS lead_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    activity_type TEXT NOT NULL, -- 'call', 'meeting', 'lead_added', 'stage_change'
    lead_id UUID REFERENCES clients(id) ON DELETE SET NULL,
    count INTEGER DEFAULT 1,
    activity_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lead_activities_dealer ON lead_activities(dealer_id, activity_date);
CREATE INDEX IF NOT EXISTS idx_lead_activities_user ON lead_activities(user_id, activity_date);

-- RLS
ALTER TABLE lead_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Dealers can view their lead activities"
    ON lead_activities
    USING (dealer_id IN (
        SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()
    ));

-- Create funnel_metrics table
CREATE TABLE IF NOT EXISTS funnel_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    stage TEXT NOT NULL,
    lead_count INTEGER NOT NULL DEFAULT 0,
    total_value DECIMAL(15,2),
    avg_days_in_stage DOUBLE PRECISION,
    conversion_rate DOUBLE PRECISION,
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(dealer_id, stage)
);

CREATE INDEX IF NOT EXISTS idx_funnel_metrics_dealer ON funnel_metrics(dealer_id);
```

### 2.5 API Design

```sql
-- Update lead stage with tracking
CREATE OR REPLACE FUNCTION update_lead_stage(
    p_client_id UUID,
    p_new_stage TEXT,
    p_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    old_stage TEXT,
    new_stage TEXT
) AS $$
DECLARE
    v_old_stage TEXT;
    v_dealer_id UUID;
BEGIN
    -- Get current stage and dealer
    SELECT lead_stage, dealer_id INTO v_old_stage, v_dealer_id
    FROM clients
    WHERE id = p_client_id;
    
    IF v_old_stage IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::TEXT, NULL::TEXT;
        RETURN;
    END IF;
    
    -- Update client
    UPDATE clients SET
        lead_stage = p_new_stage,
        updated_at = NOW(),
        last_contact_date = CURRENT_DATE
    WHERE id = p_client_id;
    
    -- Log stage change interaction
    INSERT INTO client_interactions (
        client_id, title, detail, occurred_at,
        stage, interaction_type, lead_stage_before, lead_stage_after
    ) VALUES (
        p_client_id,
        'Stage Change',
        format('Changed from %s to %s', v_old_stage, p_new_stage),
        NOW(),
        'update',
        'note',
        v_old_stage,
        p_new_stage
    );
    
    -- Log activity
    INSERT INTO lead_activities (
        dealer_id, user_id, activity_type, lead_id, activity_date
    ) VALUES (
        v_dealer_id,
        COALESCE(p_user_id, auth.uid()),
        'stage_change',
        p_client_id,
        CURRENT_DATE
    );
    
    RETURN QUERY SELECT TRUE, v_old_stage, p_new_stage;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get funnel overview
CREATE OR REPLACE FUNCTION get_funnel_overview(p_dealer_id UUID)
RETURNS TABLE (
    stage TEXT,
    lead_count BIGINT,
    total_value DECIMAL,
    avg_days_in_stage DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.lead_stage,
        COUNT(*)::BIGINT,
        COALESCE(SUM(c.estimated_value), 0),
        AVG(CURRENT_DATE - c.created_at::date)::DOUBLE PRECISION
    FROM clients c
    WHERE c.dealer_id = p_dealer_id
    AND c.deleted_at IS NULL
    AND c.lead_stage NOT IN ('closed_won', 'closed_lost')
    GROUP BY c.lead_stage
    ORDER BY 
        CASE c.lead_stage
            WHEN 'new' THEN 0
            WHEN 'contacted' THEN 1
            WHEN 'qualified' THEN 2
            WHEN 'negotiation' THEN 3
            WHEN 'offer' THEN 4
            WHEN 'test_drive' THEN 5
            ELSE 6
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get daily activity summary
CREATE OR REPLACE FUNCTION get_daily_activity_summary(
    p_dealer_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    activity_type TEXT,
    total_count BIGINT,
    unique_users BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        la.activity_type,
        SUM(la.count)::BIGINT,
        COUNT(DISTINCT la.user_id)::BIGINT
    FROM lead_activities la
    WHERE la.dealer_id = p_dealer_id
    AND la.activity_date = p_date
    GROUP BY la.activity_type;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Calculate lead score
CREATE OR REPLACE FUNCTION calculate_lead_score(p_client_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_score INTEGER := 0;
    v_interaction_count INTEGER;
    v_last_interaction_days INTEGER;
    v_has_vehicle BOOLEAN;
    v_estimated_value DECIMAL;
BEGIN
    -- Base score for having contact info
    SELECT 
        CASE WHEN phone IS NOT NULL THEN 10 ELSE 0 END +
        CASE WHEN email IS NOT NULL THEN 5 ELSE 0 END
    INTO v_score
    FROM clients
    WHERE id = p_client_id;
    
    -- Score for interactions (max 30)
    SELECT COUNT(*) INTO v_interaction_count
    FROM client_interactions
    WHERE client_id = p_client_id;
    
    v_score := v_score + LEAST(v_interaction_count * 5, 30);
    
    -- Score for recency (max 20)
    SELECT EXTRACT(DAY FROM NOW() - occurred_at)::INTEGER INTO v_last_interaction_days
    FROM client_interactions
    WHERE client_id = p_client_id
    ORDER BY occurred_at DESC
    LIMIT 1;
    
    IF v_last_interaction_days IS NOT NULL THEN
        IF v_last_interaction_days <= 1 THEN
            v_score := v_score + 20;
        ELSIF v_last_interaction_days <= 7 THEN
            v_score := v_score + 15;
        ELSIF v_last_interaction_days <= 30 THEN
            v_score := v_score + 10;
        END IF;
    END IF;
    
    -- Score for having associated vehicle (10)
    SELECT vehicle_id IS NOT NULL INTO v_has_vehicle
    FROM clients
    WHERE id = p_client_id;
    
    IF v_has_vehicle THEN
        v_score := v_score + 10;
    END IF;
    
    -- Score for estimated value (max 25)
    SELECT estimated_value INTO v_estimated_value
    FROM clients
    WHERE id = p_client_id;
    
    IF v_estimated_value IS NOT NULL THEN
        IF v_estimated_value >= 100000 THEN
            v_score := v_score + 25;
        ELSIF v_estimated_value >= 50000 THEN
            v_score := v_score + 20;
        ELSIF v_estimated_value >= 20000 THEN
            v_score := v_score + 15;
        ELSE
            v_score := v_score + 10;
        END IF;
    END IF;
    
    RETURN LEAST(v_score, 100);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2.6 Calculation Logic

```kotlin
// LeadScoringEngine.kt
class LeadScoringEngine @Inject constructor(
    private val interactionDao: ClientInteractionDao
) {
    
    fun calculateLeadScore(client: Client): Int {
        var score = 0
        
        // Base score for contact info (max 15)
        if (!client.phone.isNullOrBlank()) score += 10
        if (!client.email.isNullOrBlank()) score += 5
        
        // Interaction score (max 30)
        val interactions = runBlocking { 
            interactionDao.getByClientId(client.id).first() 
        }
        score += min(interactions.size * 5, 30)
        
        // Recency score (max 20)
        val lastInteraction = interactions.maxByOrNull { it.occurredAt }
        lastInteraction?.let {
            val daysSince = ChronoUnit.DAYS.between(
                it.occurredAt.toInstant(), 
                Instant.now()
            )
            score += when {
                daysSince <= 1 -> 20
                daysSince <= 7 -> 15
                daysSince <= 30 -> 10
                else -> 0
            }
        }
        
        // Vehicle association (10)
        if (client.vehicleId != null) score += 10
        
        // Estimated value score (max 25)
        client.estimatedValue?.let { value ->
            score += when {
                value >= BigDecimal("100000") -> 25
                value >= BigDecimal("50000") -> 20
                value >= BigDecimal("20000") -> 15
                else -> 10
            }
        }
        
        return min(score, 100)
    }
}

// FunnelAnalytics.kt
data class FunnelStageMetrics(
    val stage: LeadStage,
    val leadCount: Int,
    val totalValue: BigDecimal,
    val avgDaysInStage: Double,
    val conversionRate: Double
)

class FunnelAnalytics @Inject constructor(
    private val clientDao: ClientDao,
    private val interactionDao: ClientInteractionDao
) {
    
    suspend fun getFunnelMetrics(dealerId: UUID): List<FunnelStageMetrics> {
        val activeStages = LeadStage.values().filter { it.isActive() }
        
        return activeStages.map { stage ->
            val clients = clientDao.getByLeadStage(stage.name, dealerId)
            
            // Calculate average days in stage
            val avgDays = clients.map { client ->
                calculateDaysInStage(client, stage)
            }.average()
            
            // Calculate conversion rate (simplified)
            val conversionRate = calculateConversionRate(stage, dealerId)
            
            FunnelStageMetrics(
                stage = stage,
                leadCount = clients.size,
                totalValue = clients.sumOf { it.estimatedValue ?: BigDecimal.ZERO },
                avgDaysInStage = avgDays,
                conversionRate = conversionRate
            )
        }
    }
    
    private fun calculateDaysInStage(client: Client, stage: LeadStage): Long {
        // Get date when client entered this stage
        val stageEntryDate = runBlocking {
            interactionDao.getStageEntryDate(client.id, stage.name)
        } ?: client.createdAt
        
        return ChronoUnit.DAYS.between(
            stageEntryDate.toInstant(),
            Instant.now()
        )
    }
    
    private suspend fun calculateConversionRate(stage: LeadStage, dealerId: UUID): Double {
        // Simplified: count transitions from this stage to next
        val transitions = interactionDao.countStageTransitions(stage.name, dealerId)
        val totalInStage = clientDao.countByLeadStage(stage.name, dealerId)
        
        return if (totalInStage > 0) {
            (transitions.toDouble() / totalInStage) * 100
        } else 0.0
    }
}
```

### 2.7 UI Components

```kotlin
// FunnelVisualization.kt
@Composable
fun FunnelChart(
    stages: List<FunnelStageMetrics>,
    modifier: Modifier = Modifier
) {
    val maxCount = stages.maxOfOrNull { it.leadCount } ?: 1
    
    Column(modifier = modifier) {
        stages.forEach { stage ->
            FunnelStageBar(
                stage = stage,
                maxCount = maxCount,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
fun FunnelStageBar(
    stage: FunnelStageMetrics,
    maxCount: Int,
    modifier: Modifier = Modifier
) {
    val widthFraction = if (maxCount > 0) stage.leadCount.toFloat() / maxCount else 0f
    
    Column(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(stage.stage.name, fontWeight = FontWeight.Medium)
            Text("${stage.leadCount} leads")
        }
        
        Spacer(modifier = Modifier.height(4.dp))
        
        Box(modifier = Modifier.fillMaxWidth()) {
            // Background
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(24.dp)
                    .background(Color.LightGray, RoundedCornerShape(4.dp))
            )
            
            // Fill
            Box(
                modifier = Modifier
                    .fillMaxWidth(widthFraction)
                    .height(24.dp)
                    .background(getStageColor(stage.stage), RoundedCornerShape(4.dp))
            )
            
            // Value label
            if (stage.totalValue > BigDecimal.ZERO) {
                Text(
                    text = formatCurrency(stage.totalValue),
                    modifier = Modifier
                        .align(Alignment.CenterEnd)
                        .padding(end = 8.dp),
                    color = Color.White,
                    fontSize = 12.sp
                )
            }
        }
        
        // Conversion rate
        if (stage.conversionRate > 0) {
            Text(
                "${String.format("%.1f", stage.conversionRate)}% conversion",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
        }
    }
}

// LeadCard.kt
@Composable
fun LeadCard(
    client: Client,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = when (client.priority) {
                5 -> Color(0xFFFFEBEE) // High priority
                4 -> Color(0xFFFFF3E0)
                else -> Color.White
            }
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text(
                        client.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    
                    client.phone?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                
                // Lead score badge
                LeadScoreBadge(score = client.leadScore)
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            
            // Stage and source
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                StageChip(stage = client.leadStage)
                client.leadSource?.let { SourceChip(source = it) }
            }
            
            // Follow-up indicator
            client.nextFollowUpDate?.let { date ->
                if (date.before(Date())) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.Warning,
                            contentDescription = null,
                            tint = Color.Red,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            "Follow-up overdue",
                            color = Color.Red,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        }
    }
}
```

### 2.8 Sync Strategy

| Entity | Sync Priority | Conflict Resolution |
|--------|---------------|---------------------|
| `clients` (new fields) | High | Server wins for stage, last write for others |
| `client_interactions` (new fields) | High | Server wins |
| `lead_activities` | Medium | Append-only, no conflicts |
| `funnel_metrics` | Low (computed) | Recalculate on client |

### 2.9 Backward Compatibility

```kotlin
// Migration
val MIGRATION_ADD_LEAD_FIELDS = object : Migration(X, Y) {
    override fun migrate(db: SupportSQLiteDatabase) {
        // Add new columns to clients
        db.execSQL("ALTER TABLE clients ADD COLUMN lead_stage TEXT DEFAULT 'new'")
        db.execSQL("ALTER TABLE clients ADD COLUMN lead_source TEXT")
        db.execSQL("ALTER TABLE clients ADD COLUMN lead_source_detail TEXT")
        db.execSQL("ALTER TABLE clients ADD COLUMN assigned_to_user_id TEXT")
        db.execSQL("ALTER TABLE clients ADD COLUMN estimated_value REAL")
        db.execSQL("ALTER TABLE clients ADD COLUMN priority INTEGER DEFAULT 0")
        db.execSQL("ALTER TABLE clients ADD COLUMN last_contact_date INTEGER")
        db.execSQL("ALTER TABLE clients ADD COLUMN next_follow_up_date INTEGER")
        db.execSQL("ALTER TABLE clients ADD COLUMN lead_score INTEGER DEFAULT 0")
        
        // Add new columns to client_interactions
        db.execSQL("ALTER TABLE client_interactions ADD COLUMN interaction_type TEXT DEFAULT 'note'")
        db.execSQL("ALTER TABLE client_interactions ADD COLUMN outcome TEXT")
        db.execSQL("ALTER TABLE client_interactions ADD COLUMN duration_minutes INTEGER")
        db.execSQL("ALTER TABLE client_interactions ADD COLUMN lead_stage_before TEXT")
        db.execSQL("ALTER TABLE client_interactions ADD COLUMN lead_stage_after TEXT")
        db.execSQL("ALTER TABLE client_interactions ADD COLUMN is_follow_up INTEGER DEFAULT 0")
        
        // Migrate existing status to lead_stage
        db.execSQL("UPDATE clients SET lead_stage = status WHERE status IS NOT NULL")
        
        // Create new tables
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS lead_activities (
                id TEXT PRIMARY KEY NOT NULL,
                user_id TEXT NOT NULL,
                activity_type TEXT NOT NULL,
                lead_id TEXT,
                count INTEGER DEFAULT 1,
                activity_date INTEGER NOT NULL,
                created_at INTEGER
            )
        """)
        
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS funnel_metrics (
                id TEXT PRIMARY KEY NOT NULL,
                stage TEXT NOT NULL,
                lead_count INTEGER DEFAULT 0,
                total_value REAL,
                avg_days_in_stage REAL,
                conversion_rate REAL,
                calculated_at INTEGER
            )
        """)
    }
}
```

---

## Feature 3: Inventory Turnover Metrics (Оборачиваемость)

### 3.1 Problem Statement
No data on:
- Average sale time
- ROI per vehicle
- "Burning" inventory sitting too long
- Turnover ratio

### 3.2 Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| IT-1 | Days in Inventory (DII): For unsold - days since purchase; For sold - days from purchase to sale | P0 |
| IT-2 | Average DII: Average of all sold vehicles | P0 |
| IT-3 | Inventory aging buckets: 0-30, 31-60, 61-90, 90+ days | P0 |
| IT-4 | ROI per vehicle: `(Sale Price - Total Cost) / Total Cost × 100` | P0 |
| IT-5 | Total Cost = Purchase Price + All Expenses + Holding Cost | P0 |
| IT-6 | "Burning" alerts: vehicles over 60/90 days | P1 |
| IT-7 | Turnover ratio: `Cost of Goods Sold / Average Inventory Value` | P1 |

### 3.3 Entity/Model Changes

#### Android (Kotlin/Room)

```kotlin
// InventoryMetrics entity
@Entity(tableName = "inventory_metrics")
data class InventoryMetrics(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val dealerId: UUID,
    
    // Overall metrics
    val totalVehicles: Int,
    val totalInventoryValue: BigDecimal,
    val avgDaysInInventory: Double,
    val medianDaysInInventory: Double,
    val turnoverRatio: Double,
    
    // Aging buckets
    val bucket0to30: Int,
    val bucket31to60: Int,
    val bucket61to90: Int,
    val bucket90plus: Int,
    
    // Value by bucket
    val value0to30: BigDecimal,
    val value31to60: BigDecimal,
    val value61to90: BigDecimal,
    val value90plus: BigDecimal,
    
    // Performance metrics
    val avgRoi: Double,
    val totalProfit: BigDecimal,
    val totalHoldingCost: BigDecimal,
    
    val calculatedAt: Date = Date()
)

// VehicleInventoryStats (per-vehicle computed stats)
@Entity(
    tableName = "vehicle_inventory_stats",
    foreignKeys = [
        ForeignKey(entity = Vehicle::class, parentColumns = ["id"], childColumns = ["vehicleId"], onDelete = ForeignKey.CASCADE)
    ]
)
data class VehicleInventoryStats(
    @PrimaryKey val vehicleId: UUID,
    val daysInInventory: Int,
    val totalExpenses: BigDecimal,
    val holdingCost: BigDecimal,
    val totalCost: BigDecimal,              // purchase + expenses + holding
    val roi: Double?,                       // null if not sold
    val profit: BigDecimal?,                // null if not sold
    val agingBucket: String,                // "0-30", "31-60", "61-90", "90+"
    val isBurning: Boolean,
    val calculatedAt: Date = Date()
)

// InventoryAlert entity
@Entity(tableName = "inventory_alerts")
data class InventoryAlert(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val vehicleId: UUID,
    val alertType: String,                  // "aging", "high_holding_cost", "low_roi"
    val severity: String,                   // "warning", "critical"
    val message: String,
    val metricValue: String,                // e.g., "95 days"
    val threshold: String,                  // e.g., "60 days"
    val isRead: Boolean = false,
    val createdAt: Date = Date(),
    val dismissedAt: Date? = null
)
```

#### iOS (CoreData/Swift)

```swift
// InventoryMetrics entity
// Attributes:
// - id: UUID
// - dealerId: UUID
// - totalVehicles: Int32
// - totalInventoryValue: Decimal
// - avgDaysInInventory: Double
// - medianDaysInInventory: Double
// - turnoverRatio: Double
// - bucket0to30: Int32
// - bucket31to60: Int32
// - bucket61to90: Int32
// - bucket90plus: Int32
// - value0to30: Decimal
// - value31to60: Decimal
// - value61to90: Decimal
// - value90plus: Decimal
// - avgRoi: Double
// - totalProfit: Decimal
// - totalHoldingCost: Decimal
// - calculatedAt: Date

// VehicleInventoryStats entity
// Attributes:
// - vehicleId: UUID
// - daysInInventory: Int32
// - totalExpenses: Decimal
// - holdingCost: Decimal
// - totalCost: Decimal
// - roi: Double?
// - profit: Decimal?
// - agingBucket: String
// - isBurning: Bool
// - calculatedAt: Date

// InventoryAlert entity
// Attributes:
// - id: UUID
// - vehicleId: UUID
// - alertType: String
// - severity: String
// - message: String
// - metricValue: String
// - threshold: String
// - isRead: Bool
// - createdAt: Date
// - dismissedAt: Date?
```

### 3.4 Database Schema (Supabase)

```sql
-- Create inventory_metrics table
CREATE TABLE IF NOT EXISTS inventory_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    
    total_vehicles INTEGER NOT NULL DEFAULT 0,
    total_inventory_value DECIMAL(15,2) DEFAULT 0,
    avg_days_in_inventory DOUBLE PRECISION,
    median_days_in_inventory DOUBLE PRECISION,
    turnover_ratio DOUBLE PRECISION,
    
    bucket_0_30 INTEGER DEFAULT 0,
    bucket_31_60 INTEGER DEFAULT 0,
    bucket_61_90 INTEGER DEFAULT 0,
    bucket_90_plus INTEGER DEFAULT 0,
    
    value_0_30 DECIMAL(15,2) DEFAULT 0,
    value_31_60 DECIMAL(15,2) DEFAULT 0,
    value_61_90 DECIMAL(15,2) DEFAULT 0,
    value_90_plus DECIMAL(15,2) DEFAULT 0,
    
    avg_roi DOUBLE PRECISION,
    total_profit DECIMAL(15,2) DEFAULT 0,
    total_holding_cost DECIMAL(15,2) DEFAULT 0,
    
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(dealer_id)
);

CREATE INDEX IF NOT EXISTS idx_inventory_metrics_dealer ON inventory_metrics(dealer_id);

-- Create vehicle_inventory_stats table
CREATE TABLE IF NOT EXISTS vehicle_inventory_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    
    days_in_inventory INTEGER NOT NULL DEFAULT 0,
    total_expenses DECIMAL(15,2) DEFAULT 0,
    holding_cost DECIMAL(15,2) DEFAULT 0,
    total_cost DECIMAL(15,2) DEFAULT 0,
    roi DOUBLE PRECISION,
    profit DECIMAL(15,2),
    aging_bucket TEXT NOT NULL DEFAULT '0-30',
    is_burning BOOLEAN DEFAULT FALSE,
    
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    
    UNIQUE(dealer_id, vehicle_id)
);

CREATE INDEX IF NOT EXISTS idx_vehicle_inventory_stats_vehicle ON vehicle_inventory_stats(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inventory_stats_burning ON vehicle_inventory_stats(is_burning) WHERE is_burning = TRUE;
CREATE INDEX IF NOT EXISTS idx_vehicle_inventory_stats_bucket ON vehicle_inventory_stats(aging_bucket);

-- Create inventory_alerts table
CREATE TABLE IF NOT EXISTS inventory_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    
    alert_type TEXT NOT NULL, -- 'aging', 'high_holding_cost', 'low_roi'
    severity TEXT NOT NULL, -- 'warning', 'critical'
    message TEXT NOT NULL,
    metric_value TEXT,
    threshold TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    dismissed_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_inventory_alerts_dealer ON inventory_alerts(dealer_id);
CREATE INDEX IF NOT EXISTS idx_inventory_alerts_unread ON inventory_alerts(dealer_id, is_read) WHERE is_read = FALSE;

-- RLS
ALTER TABLE inventory_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicle_inventory_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Dealers can view their inventory metrics"
    ON inventory_metrics USING (dealer_id IN (
        SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()
    ));

CREATE POLICY "Dealers can view their vehicle inventory stats"
    ON vehicle_inventory_stats USING (dealer_id IN (
        SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()
    ));

CREATE POLICY "Dealers can manage their inventory alerts"
    ON inventory_alerts USING (dealer_id IN (
        SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()
    ));
```

### 3.5 API Design

```sql
-- Calculate vehicle inventory stats
CREATE OR REPLACE FUNCTION calculate_vehicle_inventory_stats(p_vehicle_id UUID)
RETURNS TABLE (
    days_in_inventory INTEGER,
    total_expenses DECIMAL,
    holding_cost DECIMAL,
    total_cost DECIMAL,
    roi DOUBLE PRECISION,
    profit DECIMAL,
    aging_bucket TEXT,
    is_burning BOOLEAN
) AS $$
DECLARE
    v_vehicle RECORD;
    v_expenses DECIMAL;
    v_holding_cost DECIMAL;
    v_days INTEGER;
    v_total_cost DECIMAL;
    v_profit DECIMAL;
    v_roi DOUBLE PRECISION;
    v_bucket TEXT;
    v_is_burning BOOLEAN;
BEGIN
    -- Get vehicle
    SELECT * INTO v_vehicle FROM vehicles WHERE id = p_vehicle_id;
    
    -- Calculate days in inventory
    IF v_vehicle.status = 'sold' AND v_vehicle.sale_date IS NOT NULL THEN
        v_days := v_vehicle.sale_date::date - v_vehicle.purchase_date::date;
    ELSE
        v_days := CURRENT_DATE - v_vehicle.purchase_date::date;
    END IF;
    v_days := GREATEST(v_days, 0);
    
    -- Determine aging bucket
    v_bucket := CASE
        WHEN v_days <= 30 THEN '0-30'
        WHEN v_days <= 60 THEN '31-60'
        WHEN v_days <= 90 THEN '61-90'
        ELSE '90+'
    END;
    
    -- Is burning?
    v_is_burning := v_days > 60;
    
    -- Get expenses
    SELECT COALESCE(SUM(amount), 0) INTO v_expenses
    FROM expenses WHERE vehicle_id = p_vehicle_id AND deleted_at IS NULL;
    
    -- Get holding cost
    SELECT COALESCE(total_holding_cost, 0) INTO v_holding_cost
    FROM vehicle_holding_costs WHERE vehicle_id = p_vehicle_id;
    
    -- Calculate totals
    v_total_cost := COALESCE(v_vehicle.purchase_price, 0) + v_expenses + v_holding_cost;
    
    -- Calculate ROI if sold
    IF v_vehicle.status = 'sold' AND v_vehicle.sale_price IS NOT NULL THEN
        v_profit := v_vehicle.sale_price - v_total_cost;
        IF v_total_cost > 0 THEN
            v_roi := ROUND((v_profit / v_total_cost * 100)::numeric, 2);
        ELSE
            v_roi := 0;
        END IF;
    ELSE
        v_profit := NULL;
        v_roi := NULL;
    END IF;
    
    RETURN QUERY SELECT v_days, v_expenses, v_holding_cost, v_total_cost, v_roi, v_profit, v_bucket, v_is_burning;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Calculate inventory metrics for dealer
CREATE OR REPLACE FUNCTION calculate_inventory_metrics(p_dealer_id UUID)
RETURNS VOID AS $$
DECLARE
    v_total_vehicles INTEGER;
    v_total_value DECIMAL;
    v_avg_days DOUBLE PRECISION;
    v_median_days DOUBLE PRECISION;
    v_turnover_ratio DOUBLE PRECISION;
    v_cogs DECIMAL;
    v_avg_inventory_value DECIMAL;
BEGIN
    -- Count and value
    SELECT COUNT(*), COALESCE(SUM(purchase_price), 0)
    INTO v_total_vehicles, v_total_value
    FROM vehicles
    WHERE dealer_id = p_dealer_id AND deleted_at IS NULL AND status != 'sold';
    
    -- Average days (for sold vehicles)
    SELECT AVG(CASE 
        WHEN status = 'sold' AND sale_date IS NOT NULL 
        THEN sale_date::date - purchase_date::date
        ELSE CURRENT_DATE - purchase_date::date
    END)::DOUBLE PRECISION
    INTO v_avg_days
    FROM vehicles
    WHERE dealer_id = p_dealer_id AND deleted_at IS NULL;
    
    -- Median days (simplified)
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY 
        CASE 
            WHEN status = 'sold' AND sale_date IS NOT NULL 
            THEN sale_date::date - purchase_date::date
            ELSE CURRENT_DATE - purchase_date::date
        END
    )::DOUBLE PRECISION
    INTO v_median_days
    FROM vehicles
    WHERE dealer_id = p_dealer_id AND deleted_at IS NULL;
    
    -- Turnover ratio = COGS / Average Inventory Value
    SELECT COALESCE(SUM(sale_price), 0) INTO v_cogs
    FROM vehicles
    WHERE dealer_id = p_dealer_id AND deleted_at IS NULL AND status = 'sold'
    AND sale_date >= CURRENT_DATE - INTERVAL '1 year';
    
    -- Average inventory value (simplified: current value)
    v_avg_inventory_value := v_total_value;
    
    IF v_avg_inventory_value > 0 THEN
        v_turnover_ratio := v_cogs / v_avg_inventory_value;
    ELSE
        v_turnover_ratio := 0;
    END IF;
    
    -- Upsert metrics
    INSERT INTO inventory_metrics (
        dealer_id, total_vehicles, total_inventory_value,
        avg_days_in_inventory, median_days_in_inventory, turnover_ratio,
        calculated_at
    ) VALUES (
        p_dealer_id, v_total_vehicles, v_total_value,
        v_avg_days, v_median_days, v_turnover_ratio, NOW()
    )
    ON CONFLICT (dealer_id) DO UPDATE SET
        total_vehicles = EXCLUDED.total_vehicles,
        total_inventory_value = EXCLUDED.total_inventory_value,
        avg_days_in_inventory = EXCLUDED.avg_days_in_inventory,
        median_days_in_inventory = EXCLUDED.median_days_in_inventory,
        turnover_ratio = EXCLUDED.turnover_ratio,
        calculated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get aging bucket breakdown
CREATE OR REPLACE FUNCTION get_inventory_aging_breakdown(p_dealer_id UUID)
RETURNS TABLE (
    bucket TEXT,
    vehicle_count BIGINT,
    total_value DECIMAL,
    avg_days DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vis.aging_bucket,
        COUNT(*)::BIGINT,
        COALESCE(SUM(vis.total_cost), 0),
        AVG(vis.days_in_inventory)::DOUBLE PRECISION
    FROM vehicle_inventory_stats vis
    JOIN vehicles v ON vis.vehicle_id = v.id
    WHERE vis.dealer_id = p_dealer_id
    AND v.deleted_at IS NULL
    AND v.status != 'sold'
    GROUP BY vis.aging_bucket
    ORDER BY 
        CASE vis.aging_bucket
            WHEN '0-30' THEN 1
            WHEN '31-60' THEN 2
            WHEN '61-90' THEN 3
            ELSE 4
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get burning inventory
CREATE OR REPLACE FUNCTION get_burning_inventory(
    p_dealer_id UUID,
    p_min_days INTEGER DEFAULT 60
)
RETURNS TABLE (
    vehicle_id UUID,
    vin TEXT,
    make TEXT,
    model TEXT,
    days_in_inventory INTEGER,
    total_cost DECIMAL,
    holding_cost DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id,
        v.vin,
        v.make,
        v.model,
        vis.days_in_inventory,
        vis.total_cost,
        vis.holding_cost
    FROM vehicle_inventory_stats vis
    JOIN vehicles v ON vis.vehicle_id = v.id
    WHERE vis.dealer_id = p_dealer_id
    AND vis.is_burning = TRUE
    AND vis.days_in_inventory >= p_min_days
    AND v.deleted_at IS NULL
    AND v.status != 'sold'
    ORDER BY vis.days_in_inventory DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 3.6 Calculation Logic

```kotlin
// InventoryMetricsCalculator.kt
@Singleton
class InventoryMetricsCalculator @Inject constructor(
    private val vehicleDao: VehicleDao,
    private val expenseDao: ExpenseDao,
    private val holdingCostCalculator: HoldingCostCalculator
) {
    
    suspend fun calculateVehicleStats(vehicle: Vehicle): VehicleInventoryStats {
        val daysInInventory = calculateDaysInInventory(vehicle)
        
        // Get all expenses
        val expenses = expenseDao.getExpensesForVehicleSync(vehicle.id)
        val totalExpenses = expenses.sumOf { it.amount }
        
        // Calculate holding cost
        val holdingCostResult = holdingCostCalculator.calculateHoldingCost(vehicle)
        val holdingCost = holdingCostResult.totalHoldingCost
        
        // Total cost
        val totalCost = vehicle.purchasePrice.add(totalExpenses).add(holdingCost)
        
        // ROI and profit (if sold)
        val (roi, profit) = if (vehicle.status == "sold" && vehicle.salePrice != null) {
            val p = vehicle.salePrice.subtract(totalCost)
            val r = if (totalCost > BigDecimal.ZERO) {
                p.divide(totalCost, 4, RoundingMode.HALF_UP)
                    .multiply(BigDecimal("100"))
                    .toDouble()
            } else 0.0
            Pair(r, p)
        } else {
            Pair(null, null)
        }
        
        // Aging bucket
        val bucket = when {
            daysInInventory <= 30 -> "0-30"
            daysInInventory <= 60 -> "31-60"
            daysInInventory <= 90 -> "61-90"
            else -> "90+"
        }
        
        return VehicleInventoryStats(
            vehicleId = vehicle.id,
            daysInInventory = daysInInventory,
            totalExpenses = totalExpenses,
            holdingCost = holdingCost,
            totalCost = totalCost,
            roi = roi,
            profit = profit,
            agingBucket = bucket,
            isBurning = daysInInventory > 60
        )
    }
    
    suspend fun calculateDealerMetrics(dealerId: UUID): InventoryMetrics {
        val vehicles = vehicleDao.getAllActiveIncludingSold()
        val stats = vehicles.map { calculateVehicleStats(it) }
        
        val activeStats = stats.filter { it.agingBucket.isNotEmpty() }
        val soldStats = stats.filter { it.roi != null }
        
        // Aging buckets
        val bucketCounts = activeStats.groupingBy { it.agingBucket }.eachCount()
        val bucketValues = activeStats.groupBy { it.agingBucket }
            .mapValues { (_, list) -> list.sumOf { it.totalCost } }
        
        return InventoryMetrics(
            dealerId = dealerId,
            totalVehicles = activeStats.size,
            totalInventoryValue = activeStats.sumOf { it.totalCost },
            avgDaysInInventory = activeStats.map { it.daysInInventory }.average(),
            medianDaysInInventory = activeStats.map { it.daysInInventory }.median(),
            turnoverRatio = calculateTurnoverRatio(dealerId),
            bucket0to30 = bucketCounts["0-30"] ?: 0,
            bucket31to60 = bucketCounts["31-60"] ?: 0,
            bucket61to90 = bucketCounts["61-90"] ?: 0,
            bucket90plus = bucketCounts["90+"] ?: 0,
            value0to30 = bucketValues["0-30"] ?: BigDecimal.ZERO,
            value31to60 = bucketValues["31-60"] ?: BigDecimal.ZERO,
            value61to90 = bucketValues["61-90"] ?: BigDecimal.ZERO,
            value90plus = bucketValues["90+"] ?: BigDecimal.ZERO,
            avgRoi = soldStats.map { it.roi!! }.average(),
            totalProfit = soldStats.sumOf { it.profit ?: BigDecimal.ZERO },
            totalHoldingCost = stats.sumOf { it.holdingCost }
        )
    }
    
    private fun calculateDaysInInventory(vehicle: Vehicle): Int {
        val endDate = if (vehicle.status == "sold" && vehicle.saleDate != null) {
            vehicle.saleDate
        } else Date()
        val diffMillis = endDate.time - vehicle.purchaseDate.time
        return max(0, (diffMillis / (1000 * 60 * 60 * 24)).toInt())
    }
    
    private suspend fun calculateTurnoverRatio(dealerId: UUID): Double {
        // COGS (Cost of Goods Sold) = sum of total costs for sold vehicles in last year
        val oneYearAgo = Date(System.currentTimeMillis() - 365L * 24 * 60 * 60 * 1000)
        val soldVehicles = vehicleDao.getSoldSince(oneYearAgo)
        val cogs = soldVehicles.sumOf { 
            calculateVehicleStats(it).totalCost 
        }
        
        // Average inventory value = current inventory value
        val currentInventory = vehicleDao.getAllActive()
        val avgInventory = currentInventory.sumOf { it.purchasePrice }
        
        return if (avgInventory > BigDecimal.ZERO) {
            cogs.divide(avgInventory, 4, RoundingMode.HALF_UP).toDouble()
        } else 0.0
    }
    
    private fun List<Int>.median(): Double {
        if (isEmpty()) return 0.0
        val sorted = sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) {
            (sorted[middle - 1] + sorted[middle]) / 2.0
        } else {
            sorted[middle].toDouble()
        }
    }
    
    private fun List<Double>.median(): Double {
        if (isEmpty()) return 0.0
        val sorted = sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) {
            (sorted[middle - 1] + sorted[middle]) / 2.0
        } else {
            sorted[middle]
        }
    }
}
```

### 3.7 UI Components

```kotlin
// InventoryAgingChart.kt
@Composable
fun InventoryAgingChart(
    metrics: InventoryMetrics,
    modifier: Modifier = Modifier
) {
    val buckets = listOf(
        "0-30 days" to (metrics.bucket0to30 to metrics.value0to30),
        "31-60 days" to (metrics.bucket31to60 to metrics.value31to60),
        "61-90 days" to (metrics.bucket61to90 to metrics.value61to90),
        "90+ days" to (metrics.bucket90plus to metrics.value90plus)
    )
    
    val maxCount = buckets.maxOfOrNull { it.second.first } ?: 1
    
    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                "Inventory Aging",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            
            Spacer(modifier = Modifier.height(16.dp))
            
            buckets.forEach { (label, data) ->
                val (count, value) = data
                AgingBar(
                    label = label,
                    count = count,
                    value = value,
                    maxCount = maxCount,
                    color = when (label) {
                        "0-30 days" -> Color(0xFF4CAF50)
                        "31-60 days" -> Color(0xFFFFC107)
                        "61-90 days" -> Color(0xFFFF9800)
                        else -> Color(0xFFF44336)
                    }
                )
                Spacer(modifier = Modifier.height(12.dp))
            }
        }
    }
}

@Composable
fun AgingBar(
    label: String,
    count: Int,
    value: BigDecimal,
    maxCount: Int,
    color: Color
) {
    val fraction = if (maxCount > 0) count.toFloat() / maxCount else 0f
    
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(label, fontWeight = FontWeight.Medium)
            Text("$count vehicles")
        }
        
        Spacer(modifier = Modifier.height(4.dp))
        
        Box(modifier = Modifier.fillMaxWidth()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(20.dp)
                    .background(Color.LightGray, RoundedCornerShape(4.dp))
            )
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction)
                    .height(20.dp)
                    .background(color, RoundedCornerShape(4.dp))
            )
        }
        
        Text(
            formatCurrency(value),
            style = MaterialTheme.typography.bodySmall,
            color = Color.Gray
        )
    }
}

// BurningInventoryAlert.kt
@Composable
fun BurningInventoryAlert(
    burningVehicles: List<VehicleInventoryStats>,
    onViewAll: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (burningVehicles.isEmpty()) return
    
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFFFEBEE))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = Color(0xFFF44336)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    "${burningVehicles.size} vehicles need attention",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color(0xFFD32F2F),
                    fontWeight = FontWeight.Bold
                )
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Text(
                "These vehicles have been in inventory for over 60 days",
                style = MaterialTheme.typography.bodyMedium
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            TextButton(onClick = onViewAll) {
                Text("View All")
            }
        }
    }
}

// ROICard.kt
@Composable
fun ROICard(
    roi: Double,
    profit: BigDecimal,
    modifier: Modifier = Modifier
) {
    val isPositive = roi >= 0
    
    Card(modifier = modifier) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                "ROI",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Text(
                "${String.format("%.1f", roi)}%",
                style = MaterialTheme.typography.headlineLarge,
                color = if (isPositive) Color(0xFF4CAF50) else Color(0xFFF44336),
                fontWeight = FontWeight.Bold
            )
            
            Spacer(modifier = Modifier.height(4.dp))
            
            Text(
                formatCurrency(profit),
                style = MaterialTheme.typography.bodyLarge,
                color = if (isPositive) Color(0xFF4CAF50) else Color(0xFFF44336)
            )
        }
    }
}
```

### 3.8 Sync Strategy

| Entity | Sync Priority | Conflict Resolution |
|--------|---------------|---------------------|
| `vehicle_inventory_stats` | Low (computed) | Recalculate on client, server RPC for batch |
| `inventory_metrics` | Low (computed) | Recalculate on client |
| `inventory_alerts` | Medium | Server wins |

### 3.9 Backward Compatibility

```kotlin
// Migration
val MIGRATION_ADD_INVENTORY_METRICS = object : Migration(X, Y) {
    override fun migrate(db: SupportSQLiteDatabase) {
        // Create inventory_metrics table
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS inventory_metrics (
                id TEXT PRIMARY KEY NOT NULL,
                dealer_id TEXT NOT NULL,
                total_vehicles INTEGER NOT NULL DEFAULT 0,
                total_inventory_value REAL DEFAULT 0,
                avg_days_in_inventory REAL,
                median_days_in_inventory REAL,
                turnover_ratio REAL,
                bucket_0_30 INTEGER DEFAULT 0,
                bucket_31_60 INTEGER DEFAULT 0,
                bucket_61_90 INTEGER DEFAULT 0,
                bucket_90_plus INTEGER DEFAULT 0,
                value_0_30 REAL DEFAULT 0,
                value_31_60 REAL DEFAULT 0,
                value_61_90 REAL DEFAULT 0,
                value_90_plus REAL DEFAULT 0,
                avg_roi REAL,
                total_profit REAL DEFAULT 0,
                total_holding_cost REAL DEFAULT 0,
                calculated_at INTEGER
            )
        """)
        
        // Create vehicle_inventory_stats table
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS vehicle_inventory_stats (
                vehicle_id TEXT PRIMARY KEY NOT NULL,
                days_in_inventory INTEGER NOT NULL DEFAULT 0,
                total_expenses REAL DEFAULT 0,
                holding_cost REAL DEFAULT 0,
                total_cost REAL DEFAULT 0,
                roi REAL,
                profit REAL,
                aging_bucket TEXT NOT NULL DEFAULT '0-30',
                is_burning INTEGER DEFAULT 0,
                calculated_at INTEGER
            )
        """)
        
        // Create inventory_alerts table
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS inventory_alerts (
                id TEXT PRIMARY KEY NOT NULL,
                vehicle_id TEXT NOT NULL,
                alert_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                message TEXT NOT NULL,
                metric_value TEXT,
                threshold TEXT,
                is_read INTEGER DEFAULT 0,
                created_at INTEGER,
                dismissed_at INTEGER
            )
        """)
    }
}
```

---

## Cross-Cutting Concerns

### 4.1 Sync Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        SYNC FLOW                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────┐  │
│  │   Android    │◄────►│  Supabase    │◄────►│   iOS    │  │
│  │  (Room)      │      │  (Postgres)  │      │ (CoreData)│  │
│  └──────────────┘      └──────────────┘      └──────────┘  │
│         │                     │                    │        │
│         │                     │                    │        │
│         ▼                     ▼                    ▼        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Computed Tables (No Sync)               │  │
│  │  • vehicle_holding_costs                             │  │
│  │  • vehicle_inventory_stats                           │  │
│  │  • funnel_metrics                                    │  │
│  │  • inventory_metrics                                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Computed Data Strategy:**
- Computed tables are NOT synced between devices
- Each device calculates locally from base data
- Server provides RPC functions for batch calculations
- Nightly cron job recalculates on server for analytics

### 4.2 Migration Plan

#### Phase 1: Schema Updates (Week 1)
1. Deploy Supabase migrations
2. Update Android Room schema + migrations
3. Update iOS CoreData model
4. Deploy app updates to TestFlight/Internal Testing

#### Phase 2: Data Migration (Week 2)
1. Backfill `expenses.category_type` with 'operational'
2. Backfill `clients.lead_stage` from `status`
3. Run initial calculations for all dealers
4. Verify data integrity

#### Phase 3: Feature Rollout (Week 3-4)
1. Enable for beta users
2. Monitor sync performance
3. Collect feedback
4. Gradual rollout to production

#### Phase 4: Cleanup (Week 5)
1. Remove deprecated fields (if any)
2. Archive old data
3. Update documentation

### 4.3 Performance Considerations

| Feature | Data Volume | Query Strategy |
|---------|-------------|----------------|
| Holding Cost | O(vehicles) | Calculate on-demand, cache in memory |
| CRM Funnel | O(clients × interactions) | Paginated queries, index on stage/date |
| Inventory Metrics | O(vehicles) | Background calculation, cache results |

**Optimization Strategies:**
1. Use `WorkManager` (Android) / `BGTaskScheduler` (iOS) for background calculations
2. Cache computed results in memory with 5-minute TTL
3. Use database indexes on frequently queried columns
4. Implement pagination for large datasets

### 4.4 Security & RLS

All new tables follow existing RLS patterns:

```sql
-- Template for new table RLS
ALTER TABLE new_table ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Dealers can access their data"
    ON new_table
    USING (dealer_id IN (
        SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()
    ));
```

### 4.5 Testing Strategy

| Test Type | Coverage |
|-----------|----------|
| Unit Tests | Calculation logic, data transformations |
| Integration Tests | Sync behavior, migration paths |
| UI Tests | Critical user flows |
| Performance Tests | Large dataset handling |

---

## Appendix A: Complete SQL Migration Script

```sql
-- ============================================================
-- CarDealerTracker v2.0 Database Migration
-- Run this in Supabase SQL Editor
-- ============================================================

-- Start transaction
BEGIN;

-- ============================================================
-- Feature 1: Holding Cost
-- ============================================================

-- Add category_type to expenses
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS category_type TEXT DEFAULT 'operational';
CREATE INDEX IF NOT EXISTS idx_expenses_category_type ON expenses(category_type) WHERE deleted_at IS NULL;

-- Create holding_cost_settings
CREATE TABLE IF NOT EXISTS holding_cost_settings (
    id UUID PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::UUID,
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    annual_rate_percent DECIMAL(5,2) NOT NULL DEFAULT 15.0,
    daily_rate_percent DECIMAL(10,6) NOT NULL DEFAULT 0.041096,
    alert_threshold_days INTEGER NOT NULL DEFAULT 60,
    alert_threshold_cost_percent DECIMAL(5,2) NOT NULL DEFAULT 10.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(dealer_id)
);

ALTER TABLE holding_cost_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Dealers can manage holding cost settings"
    ON holding_cost_settings
    USING (dealer_id IN (SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()));

-- Create vehicle_holding_costs
CREATE TABLE IF NOT EXISTS vehicle_holding_costs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    days_in_inventory INTEGER NOT NULL DEFAULT 0,
    daily_rate DECIMAL(10,6) NOT NULL,
    capital_tied_up DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_holding_cost DECIMAL(15,2) NOT NULL DEFAULT 0,
    should_alert BOOLEAN DEFAULT FALSE,
    last_calculated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(dealer_id, vehicle_id)
);

CREATE INDEX IF NOT EXISTS idx_vehicle_holding_costs_vehicle ON vehicle_holding_costs(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_holding_costs_alert ON vehicle_holding_costs(should_alert) WHERE should_alert = TRUE;

ALTER TABLE vehicle_holding_costs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Dealers can view vehicle holding costs"
    ON vehicle_holding_costs
    USING (dealer_id IN (SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()));

-- ============================================================
-- Feature 2: CRM/Leads Funnel
-- ============================================================

-- Add lead columns to clients
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_stage TEXT DEFAULT 'new';
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_source TEXT;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_source_detail TEXT;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS assigned_to_user_id UUID REFERENCES auth.users(id);
ALTER TABLE clients ADD COLUMN IF NOT EXISTS estimated_value DECIMAL(15,2);
ALTER TABLE clients ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 0;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS last_contact_date DATE;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS next_follow_up_date DATE;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_score INTEGER DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_clients_lead_stage ON clients(lead_stage) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_clients_lead_source ON clients(lead_source) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_clients_assigned ON clients(assigned_to_user_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_clients_next_followup ON clients(next_follow_up_date) WHERE deleted_at IS NULL AND next_follow_up_date IS NOT NULL;

-- Migrate existing status to lead_stage
UPDATE clients SET lead_stage = status WHERE status IS NOT NULL AND lead_stage = 'new';

-- Add interaction columns
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS interaction_type TEXT DEFAULT 'note';
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS outcome TEXT;
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS duration_minutes INTEGER;
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS lead_stage_before TEXT;
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS lead_stage_after TEXT;
ALTER TABLE client_interactions ADD COLUMN IF NOT EXISTS is_follow_up BOOLEAN DEFAULT FALSE;

-- Create lead_activities
CREATE TABLE IF NOT EXISTS lead_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    activity_type TEXT NOT NULL,
    lead_id UUID REFERENCES clients(id) ON DELETE SET NULL,
    count INTEGER DEFAULT 1,
    activity_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lead_activities_dealer ON lead_activities(dealer_id, activity_date);
CREATE INDEX IF NOT EXISTS idx_lead_activities_user ON lead_activities(user_id, activity_date);

ALTER TABLE lead_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Dealers can view lead activities"
    ON lead_activities
    USING (dealer_id IN (SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()));

-- Create funnel_metrics
CREATE TABLE IF NOT EXISTS funnel_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    stage TEXT NOT NULL,
    lead_count INTEGER NOT NULL DEFAULT 0,
    total_value DECIMAL(15,2),
    avg_days_in_stage DOUBLE PRECISION,
    conversion_rate DOUBLE PRECISION,
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(dealer_id, stage)
);

CREATE INDEX IF NOT EXISTS idx_funnel_metrics_dealer ON funnel_metrics(dealer_id);

ALTER TABLE funnel_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Dealers can view funnel metrics"
    ON funnel_metrics
    USING (dealer_id IN (SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()));

-- ============================================================
-- Feature 3: Inventory Turnover Metrics
-- ============================================================

-- Create inventory_metrics
CREATE TABLE IF NOT EXISTS inventory_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    total_vehicles INTEGER NOT NULL DEFAULT 0,
    total_inventory_value DECIMAL(15,2) DEFAULT 0,
    avg_days_in_inventory DOUBLE PRECISION,
    median_days_in_inventory DOUBLE PRECISION,
    turnover_ratio DOUBLE PRECISION,
    bucket_0_30 INTEGER DEFAULT 0,
    bucket_31_60 INTEGER DEFAULT 0,
    bucket_61_90 INTEGER DEFAULT 0,
    bucket_90_plus INTEGER DEFAULT 0,
    value_0_30 DECIMAL(15,2) DEFAULT 0,
    value_31_60 DECIMAL(15,2) DEFAULT 0,
    value_61_90 DECIMAL(15,2) DEFAULT 0,
    value_90_plus DECIMAL(15,2) DEFAULT 0,
    avg_roi DOUBLE PRECISION,
    total_profit DECIMAL(15,2) DEFAULT 0,
    total_holding_cost DECIMAL(15,2) DEFAULT 0,
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(dealer_id)
);

CREATE INDEX IF NOT EXISTS idx_inventory_metrics_dealer ON inventory_metrics(dealer_id);

ALTER TABLE inventory_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Dealers can view inventory metrics"
    ON inventory_metrics
    USING (dealer_id IN (SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()));

-- Create vehicle_inventory_stats
CREATE TABLE IF NOT EXISTS vehicle_inventory_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    days_in_inventory INTEGER NOT NULL DEFAULT 0,
    total_expenses DECIMAL(15,2) DEFAULT 0,
    holding_cost DECIMAL(15,2) DEFAULT 0,
    total_cost DECIMAL(15,2) DEFAULT 0,
    roi DOUBLE PRECISION,
    profit DECIMAL(15,2),
    aging_bucket TEXT NOT NULL DEFAULT '0-30',
    is_burning BOOLEAN DEFAULT FALSE,
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(dealer_id, vehicle_id)
);

CREATE INDEX IF NOT EXISTS idx_vehicle_inventory_stats_vehicle ON vehicle_inventory_stats(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_inventory_stats_burning ON vehicle_inventory_stats(is_burning) WHERE is_burning = TRUE;
CREATE INDEX IF NOT EXISTS idx_vehicle_inventory_stats_bucket ON vehicle_inventory_stats(aging_bucket);

ALTER TABLE vehicle_inventory_stats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Dealers can view vehicle inventory stats"
    ON vehicle_inventory_stats
    USING (dealer_id IN (SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()));

-- Create inventory_alerts
CREATE TABLE IF NOT EXISTS inventory_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES dealers(id) ON DELETE CASCADE,
    vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    alert_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    message TEXT NOT NULL,
    metric_value TEXT,
    threshold TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    dismissed_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_inventory_alerts_dealer ON inventory_alerts(dealer_id);
CREATE INDEX IF NOT EXISTS idx_inventory_alerts_unread ON inventory_alerts(dealer_id, is_read) WHERE is_read = FALSE;

ALTER TABLE inventory_alerts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Dealers can manage inventory alerts"
    ON inventory_alerts
    USING (dealer_id IN (SELECT dealer_id FROM dealer_users WHERE user_id = auth.uid()));

COMMIT;
```

---

## Appendix B: Enum Reference

### ExpenseCategoryType
| Value | Description |
|-------|-------------|
| `holding_cost` | Costs incurred while holding vehicle (storage, insurance) |
| `improvement` | Adds value to vehicle (repairs, detailing) |
| `operational` | General business expenses |
| `marketing` | Advertising, listing fees |

### LeadStage
| Value | Order | Description |
|-------|-------|-------------|
| `new` | 0 | Just added, no contact yet |
| `contacted` | 1 | Initial contact made |
| `qualified` | 2 | Needs assessed, budget confirmed |
| `negotiation` | 3 | Active price negotiation |
| `offer` | 4 | Formal offer made |
| `test_drive` | 5 | Test drive scheduled/completed |
| `closed_won` | 6 | Sale completed |
| `closed_lost` | 7 | Lost opportunity |

### LeadSource
| Value | Description |
|-------|-------------|
| `facebook` | Facebook lead |
| `dubizzle` | Dubizzle listing |
| `instagram` | Instagram lead |
| `referral` | Customer referral |
| `walk_in` | Walk-in customer |
| `phone` | Phone inquiry |
| `website` | Website form |
| `other` | Other source |

### AgingBucket
| Value | Range |
|-------|-------|
| `0-30` | 0-30 days in inventory |
| `31-60` | 31-60 days in inventory |
| `61-90` | 61-90 days in inventory |
| `90+` | 90+ days in inventory |

---

## Document Information

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Date | 2026-01-31 |
| Author | Architect Mode |
| Status | Draft for Review |
| Target Release | v2.0 |
