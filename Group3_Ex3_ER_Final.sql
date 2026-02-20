-- ============================================================
-- Group 3 | GBP DataSource | Exercise 3 | T431
-- File:    Group3_Ex3_ER_Final.sql
-- Dataset: E2_GBP_DataSource_aligned_FIXED.xlsx
-- Total Revenue: $2,296,919  |  Total Profit: $286,409  |  Margin: 12.5%
-- Total Orders: 5,009  |  Period: 2018 – 2021
--
-- HOW TO RUN:
--   Highlight each section and press Cmd+Enter to run one at a time.
--   Always run Sections 1 → 2 → 3 first, then any SELECT query.
-- ============================================================


-- ============================================================
-- SECTION 1: OPEN THE DATABASE
-- "USE" tells MySQL which database folder to work in.
-- ============================================================

USE GBP_DataSource;


-- ============================================================
-- SECTION 2: REBUILD THE executive_report TABLE
--
-- DROP TABLE  = delete the old placeholder (safe, it was empty)
-- CREATE TABLE = build fresh with proper columns
-- Each line:  column_name   data_type   rules
--   INT           = whole number
--   VARCHAR(n)    = text up to n characters
--   DECIMAL(14,4) = number with up to 14 digits, 4 decimal places
--   NOT NULL      = this column must always have a value
--   DEFAULT 0     = if no value given, use 0
--   AUTO_INCREMENT= automatically assign 1, 2, 3... as ID
-- ============================================================

DROP TABLE IF EXISTS `executive_report`;

CREATE TABLE `executive_report` (
    `report_row_id`  INT           NOT NULL AUTO_INCREMENT,
    `Year`           INT           NOT NULL,
    `Region`         VARCHAR(20)   NOT NULL,
    `Segment`        VARCHAR(20)   NOT NULL,
    `Category`       VARCHAR(30)   NOT NULL,
    `SubCategory`    VARCHAR(30)   NOT NULL,
    `TotalRevenue`   DECIMAL(14,4) NOT NULL DEFAULT 0,
    `TotalProfit`    DECIMAL(14,4) NOT NULL DEFAULT 0,
    `ProfitMargin`   DECIMAL(8,4)  NOT NULL DEFAULT 0,
    `TotalOrders`    INT           NOT NULL DEFAULT 0,
    `TotalUnits`     INT           NOT NULL DEFAULT 0,
    PRIMARY KEY (`report_row_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================
-- SECTION 3: FILL THE TABLE (ETL — Transform & Load step)
--
-- INSERT INTO = add rows to a table
-- SELECT      = define what data to add
-- JOIN        = link two tables by a shared column (like VLOOKUP)
--   t = transaction table  (every sale line)
--   o = order table        (order dates, ship info)
--   c = customer table     (segment)
--   l = location table     (city, state, postal code)
--   m = manager table      (region)
--   p = product table      (category, sub-category)
-- GROUP BY    = collapse rows into one per unique combination
-- SUM()       = add up all values in the group
-- COUNT(DISTINCT) = count unique values (e.g. unique orders)
-- NULLIF(x,0) = return NULL instead of 0 to avoid divide-by-zero
-- ROUND(x, 4) = round to 4 decimal places
-- ============================================================

INSERT INTO executive_report
    (Year, Region, Segment, Category, SubCategory,
     TotalRevenue, TotalProfit, ProfitMargin, TotalOrders, TotalUnits)
SELECT
    YEAR(o.OrderDate)                                                   AS Year,
    m.Region,
    c.Segment,
    p.Category,
    p.`Sub-Category`                                                    AS SubCategory,
    ROUND(SUM(t.Sales),    4)                                           AS TotalRevenue,
    ROUND(SUM(t.Profit),   4)                                           AS TotalProfit,
    ROUND(SUM(t.Profit) / NULLIF(SUM(t.Sales), 0), 4)                  AS ProfitMargin,
    COUNT(DISTINCT o.OrderID)                                           AS TotalOrders,
    SUM(t.Quantity)                                                     AS TotalUnits
FROM       `transaction`  t
JOIN       `order`        o  ON t.OrderID    = o.OrderID
JOIN       `customer`     c  ON o.CustomerID = c.CustomerID
JOIN       `location`     l  ON o.LocationID = l.LocationID
LEFT JOIN  `manager`      m  ON l.ManagerID  = m.ManagerID
JOIN       `product`      p  ON t.ProductID  = p.ProductID
WHERE      o.OrderDate IS NOT NULL
GROUP BY   YEAR(o.OrderDate), m.Region, c.Segment,
           p.Category, p.`Sub-Category`;

-- Verify: should be ~192 rows
SELECT COUNT(*) AS rows_inserted FROM executive_report;


-- ============================================================
-- HOW THE REPORT QUERIES BELOW WORK:
--
-- SUM(CASE WHEN Year=2018 THEN TotalRevenue ELSE 0 END)
--   → "if this row is for 2018, use TotalRevenue; otherwise 0"
--   This is how SQL pivots rows into columns.
--
-- (new - old) / ABS(old) * 100
--   → Year-over-Year % change formula
--   ABS() = absolute value (handles negative profit correctly)
--
-- Participation Ratio = this group's value / total for that year
--   The (SELECT SUM(...) WHERE Year=X) is a subquery —
--   it runs a separate calculation just for that one number.
--
-- GROUP BY x WITH ROLLUP
--   → groups by x, then adds one extra grand total row
--
-- COALESCE(x, 'TOTAL')
--   → the grand total row has NULL for the group column;
--     this replaces NULL with the word "TOTAL"
-- ============================================================

-- ============================================================
-- SECTION 4: GROSS SALES REVENUE BY REGION
-- --   West: $147,883 | $139,966 | $187,480 | $250,128
--   East: $128,399 | $156,332 | $180,686 | $213,083
--   South: $103,846 | $71,360 | $93,610 | $122,906
--   Central: $103,838 | $102,874 | $147,429 | $147,098
--   TOTAL: $483,966 | $470,533 | $609,206 | $733,215
-- ============================================================

SELECT
    COALESCE(Region, 'TOTAL')                                            AS `Region`,

    ROUND(SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END), 0)         AS `2018 ($)`,
    ROUND(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END), 0)         AS `2019 ($)`,

    -- Year-over-Year: (new - old) / old × 100
    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2019 vs 2018`,

    ROUND(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END), 0)         AS `2020 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2020 vs 2019`,

    ROUND(SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END), 0)         AS `2021 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2021 vs 2020`,

    -- Participation Ratio: this row's share of the total for that year
    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END)
      / (SELECT SUM(TotalRevenue) FROM executive_report WHERE Year = 2018)
      * 100, 1), '%')                                                   AS `Part. Ratio 2018`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END)
      / (SELECT SUM(TotalRevenue) FROM executive_report WHERE Year = 2021)
      * 100, 1), '%')                                                   AS `Part. Ratio 2021`

FROM executive_report
GROUP BY Region WITH ROLLUP
ORDER BY
    CASE Region
        WHEN 'West' THEN 1
        WHEN 'East' THEN 2
        WHEN 'South' THEN 3
        WHEN 'Central' THEN 4
        ELSE 99
    END;

-- ============================================================
-- SECTION 5: GROSS PROFIT BY REGION
-- --   West: $20,066 | $20,492 | $24,052 | $43,809
--   East: $17,072 | $21,091 | $20,142 | $33,231
--   South: $11,879 | $8,319 | $17,703 | $8,849
--   Central: $540 | $11,717 | $19,899 | $7,551
--   TOTAL: $49,556 | $61,619 | $81,795 | $93,439
-- ============================================================

SELECT
    COALESCE(Region, 'TOTAL')                                            AS `Region`,

    ROUND(SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END), 0)         AS `2018 ($)`,
    ROUND(SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END), 0)         AS `2019 ($)`,

    -- Year-over-Year: (new - old) / old × 100
    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2019 vs 2018`,

    ROUND(SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END), 0)         AS `2020 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2020 vs 2019`,

    ROUND(SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END), 0)         AS `2021 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2021 vs 2020`,

    -- Participation Ratio: this row's share of the total for that year
    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END)
      / (SELECT SUM(TotalProfit) FROM executive_report WHERE Year = 2018)
      * 100, 1), '%')                                                   AS `Part. Ratio 2018`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END)
      / (SELECT SUM(TotalProfit) FROM executive_report WHERE Year = 2021)
      * 100, 1), '%')                                                   AS `Part. Ratio 2021`

FROM executive_report
GROUP BY Region WITH ROLLUP
ORDER BY
    CASE Region
        WHEN 'West' THEN 1
        WHEN 'East' THEN 2
        WHEN 'South' THEN 3
        WHEN 'Central' THEN 4
        ELSE 99
    END;

-- ============================================================
-- SECTION 6: PROFIT MARGIN (%) BY REGION
--
-- Margin = Profit / Revenue × 100
-- Change column = difference in percentage points (pp)
--   e.g. going from 10.2% to 13.1% = +2.9 pp
--
-- Expected results:
--   West:    13.6% | 14.6% | 12.8% | 17.5%   ← strong finish
--   East:    13.3% | 13.5% | 11.2% | 15.6%   ← recovered well
--   South:   11.4% | 11.7% | 18.9% |  7.2%   ← 2021 collapse ⚠
--   Central:  0.5% | 11.4% | 13.5% |  5.1%   ← 2021 concern  ⚠
--   TOTAL:   10.2% | 13.1% | 13.4% | 12.7%
-- ============================================================

SELECT
    COALESCE(Region, 'TOTAL')                                           AS `Region`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END), 0)
      * 100, 1), '%')                                                   AS `2018 Margin`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END), 0)
      * 100, 1), '%')                                                   AS `2019 Margin`,

    CONCAT(ROUND((
        SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END), 0)
      - SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END), 0)
    ) * 100, 1), ' pp')                                                 AS `2019 vs 2018`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END), 0)
      * 100, 1), '%')                                                   AS `2020 Margin`,

    CONCAT(ROUND((
        SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END), 0)
      - SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END), 0)
    ) * 100, 1), ' pp')                                                 AS `2020 vs 2019`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END), 0)
      * 100, 1), '%')                                                   AS `2021 Margin`,

    CONCAT(ROUND((
        SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END), 0)
      - SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)
      / NULLIF(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END), 0)
    ) * 100, 1), ' pp')                                                 AS `2021 vs 2020`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END)
      / (SELECT SUM(TotalRevenue) FROM executive_report WHERE Year = 2018)
      * 100, 1), '%')                                                   AS `Part. Ratio 2018`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END)
      / (SELECT SUM(TotalRevenue) FROM executive_report WHERE Year = 2021)
      * 100, 1), '%')                                                   AS `Part. Ratio 2021`

FROM executive_report
GROUP BY Region WITH ROLLUP
ORDER BY
    CASE Region
        WHEN 'West'    THEN 1
        WHEN 'East'    THEN 2
        WHEN 'South'   THEN 3
        WHEN 'Central' THEN 4
        ELSE 99
    END;

-- ============================================================
-- SECTION 7: GROSS SALES REVENUE BY PRODUCT CATEGORY
-- --   Technology: $175,278 | $162,781 | $226,364 | $271,731
--   Office Supplies: $151,776 | $137,233 | $183,940 | $246,097
--   Furniture: $156,911 | $170,518 | $198,901 | $215,387
--   TOTAL: $483,966 | $470,533 | $609,206 | $733,215
-- ============================================================

SELECT
    COALESCE(Category, 'TOTAL')                                            AS `Category`,

    ROUND(SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END), 0)         AS `2018 ($)`,
    ROUND(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END), 0)         AS `2019 ($)`,

    -- Year-over-Year: (new - old) / old × 100
    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2019 vs 2018`,

    ROUND(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END), 0)         AS `2020 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2020 vs 2019`,

    ROUND(SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END), 0)         AS `2021 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2021 vs 2020`,

    -- Participation Ratio: this row's share of the total for that year
    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END)
      / (SELECT SUM(TotalRevenue) FROM executive_report WHERE Year = 2018)
      * 100, 1), '%')                                                   AS `Part. Ratio 2018`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END)
      / (SELECT SUM(TotalRevenue) FROM executive_report WHERE Year = 2021)
      * 100, 1), '%')                                                   AS `Part. Ratio 2021`

FROM executive_report
GROUP BY Category WITH ROLLUP
ORDER BY
    CASE Category
        WHEN 'Technology' THEN 1
        WHEN 'Office Supplies' THEN 2
        WHEN 'Furniture' THEN 3
        ELSE 99
    END;

-- ============================================================
-- SECTION 8: GROSS PROFIT BY PRODUCT CATEGORY
-- --   Technology: $21,493 | $33,504 | $39,774 | $50,684
--   Office Supplies: $22,593 | $25,100 | $35,061 | $39,737
--   Furniture: $5,470 | $3,015 | $6,960 | $3,018
--   TOTAL: $49,556 | $61,619 | $81,795 | $93,439
-- ============================================================

SELECT
    COALESCE(Category, 'TOTAL')                                            AS `Category`,

    ROUND(SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END), 0)         AS `2018 ($)`,
    ROUND(SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END), 0)         AS `2019 ($)`,

    -- Year-over-Year: (new - old) / old × 100
    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2019 vs 2018`,

    ROUND(SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END), 0)         AS `2020 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2020 vs 2019`,

    ROUND(SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END), 0)         AS `2021 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2021 vs 2020`,

    -- Participation Ratio: this row's share of the total for that year
    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END)
      / (SELECT SUM(TotalProfit) FROM executive_report WHERE Year = 2018)
      * 100, 1), '%')                                                   AS `Part. Ratio 2018`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END)
      / (SELECT SUM(TotalProfit) FROM executive_report WHERE Year = 2021)
      * 100, 1), '%')                                                   AS `Part. Ratio 2021`

FROM executive_report
GROUP BY Category WITH ROLLUP
ORDER BY
    CASE Category
        WHEN 'Technology' THEN 1
        WHEN 'Office Supplies' THEN 2
        WHEN 'Furniture' THEN 3
        ELSE 99
    END;

-- ============================================================
-- SECTION 9: GROSS SALES REVENUE BY CUSTOMER SEGMENT
-- --   Consumer: $266,097 | $266,536 | $296,864 | $331,905
--   Corporate: $128,435 | $128,757 | $207,106 | $241,848
--   Home Office: $89,434 | $75,239 | $105,235 | $159,463
--   TOTAL: $483,966 | $470,533 | $609,206 | $733,215
-- ============================================================

SELECT
    COALESCE(Segment, 'TOTAL')                                            AS `Segment`,

    ROUND(SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END), 0)         AS `2018 ($)`,
    ROUND(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END), 0)         AS `2019 ($)`,

    -- Year-over-Year: (new - old) / old × 100
    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2019 vs 2018`,

    ROUND(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END), 0)         AS `2020 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2019 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2020 vs 2019`,

    ROUND(SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END), 0)         AS `2021 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END)
       - SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2020 THEN TotalRevenue ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2021 vs 2020`,

    -- Participation Ratio: this row's share of the total for that year
    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2018 THEN TotalRevenue ELSE 0 END)
      / (SELECT SUM(TotalRevenue) FROM executive_report WHERE Year = 2018)
      * 100, 1), '%')                                                   AS `Part. Ratio 2018`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2021 THEN TotalRevenue ELSE 0 END)
      / (SELECT SUM(TotalRevenue) FROM executive_report WHERE Year = 2021)
      * 100, 1), '%')                                                   AS `Part. Ratio 2021`

FROM executive_report
GROUP BY Segment WITH ROLLUP
ORDER BY
    CASE Segment
        WHEN 'Consumer' THEN 1
        WHEN 'Corporate' THEN 2
        WHEN 'Home Office' THEN 3
        ELSE 99
    END;

-- ============================================================
-- SECTION 10: GROSS PROFIT BY CUSTOMER SEGMENT
-- --   Consumer: $24,320 | $28,460 | $35,771 | $45,568
--   Corporate: $13,513 | $20,688 | $30,995 | $26,782
--   Home Office: $11,723 | $12,470 | $15,029 | $21,089
--   TOTAL: $49,556 | $61,619 | $81,795 | $93,439
-- ============================================================

SELECT
    COALESCE(Segment, 'TOTAL')                                            AS `Segment`,

    ROUND(SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END), 0)         AS `2018 ($)`,
    ROUND(SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END), 0)         AS `2019 ($)`,

    -- Year-over-Year: (new - old) / old × 100
    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2019 vs 2018`,

    ROUND(SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END), 0)         AS `2020 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2019 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2020 vs 2019`,

    ROUND(SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END), 0)         AS `2021 ($)`,

    CONCAT(ROUND(
        (SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END)
       - SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END))
      / NULLIF(ABS(SUM(CASE WHEN Year = 2020 THEN TotalProfit ELSE 0 END)), 0)
      * 100, 1), '%')                                                   AS `2021 vs 2020`,

    -- Participation Ratio: this row's share of the total for that year
    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2018 THEN TotalProfit ELSE 0 END)
      / (SELECT SUM(TotalProfit) FROM executive_report WHERE Year = 2018)
      * 100, 1), '%')                                                   AS `Part. Ratio 2018`,

    CONCAT(ROUND(
        SUM(CASE WHEN Year = 2021 THEN TotalProfit ELSE 0 END)
      / (SELECT SUM(TotalProfit) FROM executive_report WHERE Year = 2021)
      * 100, 1), '%')                                                   AS `Part. Ratio 2021`

FROM executive_report
GROUP BY Segment WITH ROLLUP
ORDER BY
    CASE Segment
        WHEN 'Consumer' THEN 1
        WHEN 'Corporate' THEN 2
        WHEN 'Home Office' THEN 3
        ELSE 99
    END;

-- ============================================================
-- END OF FILE
-- Group 3 | GBP DataSource | T431 | Applied A.I. Solutions
-- ============================================================
