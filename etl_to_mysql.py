#!/usr/bin/env python3
"""
etl_to_mysql.py  –  Exercise 3: Extract, Load, and create schema

Steps performed:
  1. EXTRACT  – Read each entity tab from E2_GBP_DataSource_aligned.xlsx
                and export as individual CSV files.
  2. SCHEMA   – Connect to MySQL, create the GBP_DataSource database,
                and build all tables with PRIMARY KEYs and FOREIGN KEYs
                matching the Group 3 ERD.
  3. LOAD     – Bulk-insert the CSV data into the corresponding tables.
  4. PLACEHOLDERS – Create empty operational_report and executive_report
                    tables as placeholders for the Transform step.

Usage:
    python etl_to_mysql.py

Requirements:
    pip install pandas openpyxl mysql-connector-python
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pandas as pd
import mysql.connector
from mysql.connector import Error

# ── Configuration ────────────────────────────────────────────────────
EXCEL_PATH = Path(__file__).parent / "E2_GBP_DataSource_aligned.xlsx"
CSV_DIR = Path(__file__).parent / "csv_exports"

MYSQL_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "1234",
    "port": 3306,
}

DB_NAME = "GBP_DataSource"

# Tabs to export (order matters: parents before children for FK loading)
ENTITY_TABS = ["Manager", "Product", "Customer", "Location", "Order", "Transaction"]


# ── Step 1: Extract – Excel tabs → CSV files ─────────────────────────
def extract_csvs() -> dict[str, Path]:
    """Export each entity tab from the aligned Excel as a CSV file."""
    CSV_DIR.mkdir(exist_ok=True)
    xls = pd.ExcelFile(EXCEL_PATH)
    paths: dict[str, Path] = {}

    for tab in ENTITY_TABS:
        df = pd.read_excel(xls, sheet_name=tab)
        csv_path = CSV_DIR / f"{tab}.csv"
        df.to_csv(csv_path, index=False)
        paths[tab] = csv_path
        print(f"  [EXTRACT] {tab}: {len(df)} rows → {csv_path.name}")

    return paths


# ── Step 2: Schema – CREATE DATABASE + tables with PK/FK ─────────────
# SQL uses VARCHAR sizes rounded up from the max lengths found in the data.

SCHEMA_SQL = f"""
DROP DATABASE IF EXISTS `{DB_NAME}`;
CREATE DATABASE `{DB_NAME}` DEFAULT CHARACTER SET utf8mb4;
USE `{DB_NAME}`;

-- ────────────────────────────────────────────
-- Master / Reference tables (no FK dependencies)
-- ────────────────────────────────────────────

CREATE TABLE `Manager` (
    `ManagerID`         VARCHAR(10)   NOT NULL,
    `Region`            VARCHAR(20)   NOT NULL,
    `RegionManagerName` VARCHAR(50)   NOT NULL,
    PRIMARY KEY (`ManagerID`)
) ENGINE=InnoDB;

CREATE TABLE `Product` (
    `ProductID`    VARCHAR(25)   NOT NULL,
    `Category`     VARCHAR(30)   NOT NULL,
    `Sub-Category` VARCHAR(30)   NOT NULL,
    `ProductName`  VARCHAR(255)  NOT NULL,
    PRIMARY KEY (`ProductID`)
) ENGINE=InnoDB;

CREATE TABLE `Customer` (
    `CustomerID`   VARCHAR(15)   NOT NULL,
    `CustomerName` VARCHAR(50)   NOT NULL,
    `Segment`      VARCHAR(20)   NOT NULL,
    PRIMARY KEY (`CustomerID`)
) ENGINE=InnoDB;

-- ────────────────────────────────────────────
-- Tables with FK dependencies
-- ────────────────────────────────────────────

CREATE TABLE `Location` (
    `LocationID`     VARCHAR(10)   NOT NULL,
    `ManagerID`      VARCHAR(10)   NULL,
    `PostalCode`     INT           NULL,
    `State`          VARCHAR(50)   NULL,
    `City`           VARCHAR(50)   NULL,
    `Country/Region` VARCHAR(30)   NULL,
    PRIMARY KEY (`LocationID`),
    CONSTRAINT `fk_location_manager`
        FOREIGN KEY (`ManagerID`) REFERENCES `Manager`(`ManagerID`)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE `Order` (
    `OrderID`    VARCHAR(20)   NOT NULL,
    `CustomerID` VARCHAR(15)   NOT NULL,
    `LocationID` VARCHAR(10)   NOT NULL,
    `OrderDate`  DATE          NULL,
    `ShipDate`   DATE          NULL,
    `ShipMode`   VARCHAR(20)   NULL,
    PRIMARY KEY (`OrderID`),
    CONSTRAINT `fk_order_customer`
        FOREIGN KEY (`CustomerID`) REFERENCES `Customer`(`CustomerID`)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `fk_order_location`
        FOREIGN KEY (`LocationID`) REFERENCES `Location`(`LocationID`)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE `Transaction` (
    `RowID`      INT           NOT NULL,
    `OrderID`    VARCHAR(20)   NOT NULL,
    `ProductID`  VARCHAR(25)   NOT NULL,
    `Sales`      DECIMAL(12,4) NULL,
    `Quantity`   INT           NULL,
    `Discount`   DECIMAL(5,2)  NULL,
    `Profit`     DECIMAL(12,4) NULL,
    PRIMARY KEY (`RowID`),
    CONSTRAINT `fk_transaction_order`
        FOREIGN KEY (`OrderID`) REFERENCES `Order`(`OrderID`)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT `fk_transaction_product`
        FOREIGN KEY (`ProductID`) REFERENCES `Product`(`ProductID`)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ────────────────────────────────────────────
-- Placeholder reporting tables (to be populated later)
-- ────────────────────────────────────────────

CREATE TABLE `operational_report` (
    `report_row_id` INT AUTO_INCREMENT,
    `OrderID`       VARCHAR(20) NULL,
    `ProductID`     VARCHAR(25) NULL,
    PRIMARY KEY (`report_row_id`)
) ENGINE=InnoDB;

CREATE TABLE `executive_report` (
    `report_row_id` INT AUTO_INCREMENT,
    `OrderID`       VARCHAR(20) NULL,
    `ProductID`     VARCHAR(25) NULL,
    PRIMARY KEY (`report_row_id`)
) ENGINE=InnoDB;
"""


def create_schema(conn: mysql.connector.MySQLConnection) -> None:
    """Execute the schema DDL statements."""
    cursor = conn.cursor()
    for statement in SCHEMA_SQL.split(";"):
        stmt = statement.strip()
        if stmt:
            cursor.execute(stmt)
    conn.commit()
    cursor.close()
    print("  [SCHEMA] Database and all tables created successfully.")


# ── Step 3: Load – CSV data → MySQL tables ───────────────────────────

# Column lists per table (must match CSV header order)
TABLE_COLUMNS = {
    "Manager":     ["ManagerID", "Region", "RegionManagerName"],
    "Product":     ["ProductID", "Category", "Sub-Category", "ProductName"],
    "Customer":    ["CustomerID", "CustomerName", "Segment"],
    "Location":    ["LocationID", "ManagerID", "PostalCode", "State", "City", "Country/Region"],
    "Order":       ["OrderID", "CustomerID", "LocationID", "OrderDate", "ShipDate", "ShipMode"],
    "Transaction": ["RowID", "OrderID", "ProductID", "Sales", "Quantity", "Discount", "Profit"],
}


def load_table(conn: mysql.connector.MySQLConnection, table: str, csv_path: Path) -> None:
    """Read a CSV and INSERT its rows into the corresponding MySQL table."""
    df = pd.read_csv(csv_path, keep_default_na=False, na_values=[""])
    cols = TABLE_COLUMNS[table]
    placeholders = ", ".join(["%s"] * len(cols))
    col_names = ", ".join(f"`{c}`" for c in cols)
    insert_sql = f"INSERT INTO `{table}` ({col_names}) VALUES ({placeholders})"

    cursor = conn.cursor()
    batch_size = 1000
    rows_inserted = 0

    for start in range(0, len(df), batch_size):
        batch = df.iloc[start : start + batch_size]
        values = []
        for _, row in batch.iterrows():
            row_vals = []
            for c in cols:
                v = row.get(c, None)
                # Handle NaN / NaT / empty string → NULL
                if pd.isna(v) or v == "":
                    row_vals.append(None)
                else:
                    row_vals.append(v)
            values.append(tuple(row_vals))
        cursor.executemany(insert_sql, values)
        rows_inserted += len(values)

    conn.commit()
    cursor.close()
    print(f"  [LOAD]   {table}: {rows_inserted} rows inserted.")


# ── Main ─────────────────────────────────────────────────────────────

def main() -> None:
    print("=" * 60)
    print("Exercise 3 – ETL to MySQL")
    print("=" * 60)

    # Step 1: Extract
    print("\n── Step 1: Extract (Excel → CSV) ──")
    csv_paths = extract_csvs()

    # Connect to MySQL
    try:
        conn = mysql.connector.connect(**MYSQL_CONFIG)
    except Error as e:
        print(f"\nERROR: Could not connect to MySQL.\n  {e}")
        print("Make sure MySQL is running on localhost:3306 with user=root, password=1234.")
        sys.exit(1)

    # Step 2: Schema
    print("\n── Step 2: Create Schema ──")
    create_schema(conn)

    # Reconnect with the database selected
    conn.close()
    conn = mysql.connector.connect(**MYSQL_CONFIG, database=DB_NAME)

    # Step 3: Load (order: parents first, children last)
    print("\n── Step 3: Load (CSV → MySQL) ──")
    for table in ENTITY_TABS:
        load_table(conn, table, csv_paths[table])

    # Summary
    print("\n── Verification ──")
    cursor = conn.cursor()
    for table in ENTITY_TABS + ["operational_report", "executive_report"]:
        cursor.execute(f"SELECT COUNT(*) FROM `{table}`")
        count = cursor.fetchone()[0]
        print(f"  {table:25s} → {count} rows")
    cursor.close()

    conn.close()
    print("\nDone! Database `GBP_DataSource` is ready.")


if __name__ == "__main__":
    main()
