CREATE DATABASE Customers_transactions;
UPDATE customers SET Gender = NULL WHERE Gender = "";
UPDATE customers SET Age = NULL WHERE Age = "";
ALTER TABLE customers MODIFY Age INT NULL;

SELECT * FROM customers;

CREATE TABLE transactions 
(date_new DATE,
Id_check INT,
ID_client INT,
Count_products DECIMAL(10,3),
Sum_payment DECIMAL(10,2));

LOAD DATA INFILE "C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\TRANSACTIONS_final.csv"
INTO TABLE transactions
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SHOW VARIABLES LIKE 'secure_file_priv';

SELECT * FROM customers;
SELECT * FROM transactions;

# список клиентов с непрерывной историей за год, то есть каждый месяц на регулярной основе без пропусков за указанный годовой период, 
# средний чек за период с 01.06.2015 по 01.06.2016, средняя сумма покупок за месяц, количество всех операций по клиенту за период;
# информацию в разрезе месяцев:
WITH checks AS (
    SELECT
        ID_client,
        Id_check,
        DATE_FORMAT(date_new, '%Y-%m') AS transaction_month,
        SUM(Sum_payment) AS check_sum
    FROM transactions
    WHERE date_new >= '2015-06-01'
      AND date_new < '2016-06-01'
    GROUP BY
        ID_client,
        Id_check,
        DATE_FORMAT(date_new, '%Y-%m')
),
monthly_transactions AS (
    SELECT
        ID_client,
        transaction_month,
        COUNT(*) AS operations_count,
        AVG(check_sum) AS avg_check,
        SUM(check_sum) AS total_sum
    FROM checks
    GROUP BY ID_client, transaction_month
),
clients_with_full_history AS (
    SELECT ID_client
    FROM monthly_transactions
    GROUP BY ID_client
    HAVING COUNT(DISTINCT transaction_month) = 12
)
SELECT
    ch.ID_client,
    ROUND(AVG(mt.avg_check), 2) AS avg_check_over_period,
    ROUND(AVG(mt.total_sum), 2) AS avg_monthly_payment,
    SUM(mt.operations_count) AS total_operations
FROM clients_with_full_history ch
JOIN monthly_transactions mt
    ON ch.ID_client = mt.ID_client
GROUP BY ch.ID_client
ORDER BY ch.ID_client;

# средняя сумма чека в месяц;
# среднее количество операций в месяц;
# среднее количество клиентов, которые совершали операции;
# долю от общего количества операций за год и долю в месяц от общей суммы операций;
# вывести % соотношение M/F/NA в каждом месяце с их долей затрат;

WITH checks AS (
        SELECT
        t.ID_client,
        t.Id_check,
        DATE_FORMAT(t.date_new, '%Y-%m') AS month,
        SUM(t.Sum_payment) AS check_sum
    FROM transactions t
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new < '2016-06-01'
    GROUP BY
        t.ID_client,
        t.Id_check,
        DATE_FORMAT(t.date_new, '%Y-%m')
),

checks_with_gender AS (
    SELECT
        ch.month,
        ch.ID_client,
        ch.Id_check,
        ch.check_sum,
        CASE
            WHEN c.Gender IN ('M', 'F') THEN c.Gender
            ELSE 'NA'
        END AS gender
    FROM checks ch
    LEFT JOIN customers c
        ON ch.ID_client = c.Id_client
),

monthly_stats AS (
    SELECT
        month,
        ROUND(AVG(check_sum), 2) AS avg_check_month,              
        COUNT(*) AS operations_count,                            
        COUNT(DISTINCT ID_client) AS clients_count,              
        SUM(check_sum) AS total_sum_month
    FROM checks_with_gender
    GROUP BY month
),

annual_totals AS (
    SELECT
        SUM(operations_count) AS total_operations_year,
        SUM(total_sum_month) AS total_sum_year
    FROM monthly_stats
),

gender_distribution AS (
    SELECT
        month,

        COUNT(DISTINCT CASE WHEN gender = 'M' THEN ID_client END) AS male_count,
        COUNT(DISTINCT CASE WHEN gender = 'F' THEN ID_client END) AS female_count,
        COUNT(DISTINCT CASE WHEN gender = 'NA' THEN ID_client END) AS na_count,

        SUM(CASE WHEN gender = 'M' THEN check_sum ELSE 0 END) AS male_spent,
        SUM(CASE WHEN gender = 'F' THEN check_sum ELSE 0 END) AS female_spent,
        SUM(CASE WHEN gender = 'NA' THEN check_sum ELSE 0 END) AS na_spent
    FROM checks_with_gender
    GROUP BY month
)

SELECT
    ms.month,
    ms.avg_check_month,
    ms.operations_count,
    ms.clients_count,

    ROUND(ms.operations_count * 100.0 / at.total_operations_year, 2) AS operations_share_year_pct,
    ROUND(ms.total_sum_month * 100.0 / at.total_sum_year, 2) AS sum_share_year_pct,

    ROUND(gd.male_count * 100.0 / ms.clients_count, 2) AS male_count_share_pct,
    ROUND(gd.female_count * 100.0 / ms.clients_count, 2) AS female_count_share_pct,
    ROUND(gd.na_count * 100.0 / ms.clients_count, 2) AS na_count_share_pct,

    ROUND(gd.male_spent * 100.0 / ms.total_sum_month, 2) AS male_spent_share_pct,
    ROUND(gd.female_spent * 100.0 / ms.total_sum_month, 2) AS female_spent_share_pct,
    ROUND(gd.na_spent * 100.0 / ms.total_sum_month, 2) AS na_spent_share_pct

FROM monthly_stats ms
CROSS JOIN annual_totals at
JOIN gender_distribution gd
    ON ms.month = gd.month
ORDER BY ms.month;

# возрастные группы клиентов с шагом 10 лет и отдельно клиентов, у которых нет данной информации, 
# с параметрами сумма и количество операций за весь период, и поквартально - средние показатели и %.
WITH checks AS (
    -- 1 чек = 1 строка
    SELECT
        t.ID_client,
        t.Id_check,
        QUARTER(t.date_new) AS quarter,
        SUM(t.Sum_payment) AS check_sum
    FROM transactions t
    WHERE t.date_new >= '2015-06-01'
      AND t.date_new < '2016-06-01'
    GROUP BY
        t.ID_client,
        t.Id_check,
        QUARTER(t.date_new)
),

age_groups AS (
    SELECT
        ch.ID_client,
        ch.Id_check,
        ch.quarter,
        ch.check_sum,
        CASE
            WHEN c.Age IS NULL THEN 'NA'
            WHEN c.Age BETWEEN 0 AND 9 THEN '0-9'
            WHEN c.Age BETWEEN 10 AND 19 THEN '10-19'
            WHEN c.Age BETWEEN 20 AND 29 THEN '20-29'
            WHEN c.Age BETWEEN 30 AND 39 THEN '30-39'
            WHEN c.Age BETWEEN 40 AND 49 THEN '40-49'
            WHEN c.Age BETWEEN 50 AND 59 THEN '50-59'
            WHEN c.Age BETWEEN 60 AND 69 THEN '60-69'
            WHEN c.Age BETWEEN 70 AND 79 THEN '70-79'
            ELSE '80+'
        END AS age_group
    FROM checks ch
    LEFT JOIN customers c
        ON ch.ID_client = c.Id_client
),

quarterly_stats AS (
    SELECT
        age_group,
        quarter,
        COUNT(*) AS quarterly_operations,
        COUNT(DISTINCT ID_client) AS clients_per_quarter,
        SUM(check_sum) AS quarterly_sum,
        AVG(check_sum) AS avg_sum_per_operation
    FROM age_groups
    GROUP BY age_group, quarter
),

annual_stats AS (
    SELECT
        age_group,
        SUM(quarterly_operations) AS total_operations_year,
        SUM(quarterly_sum) AS total_sum_year
    FROM quarterly_stats
    GROUP BY age_group
)

SELECT
    qs.age_group,
    qs.quarter,
    qs.quarterly_operations,
    ROUND(qs.quarterly_sum, 2) AS quarterly_sum,
    ROUND(qs.avg_sum_per_operation, 2) AS avg_sum_per_operation,
    qs.clients_per_quarter,

    ROUND(qs.quarterly_operations * 100.0 / ast.total_operations_year, 2) AS operation_share_quarter,
    ROUND(qs.quarterly_sum * 100.0 / ast.total_sum_year, 2) AS sum_share_quarter

FROM quarterly_stats qs
JOIN annual_stats ast
    ON qs.age_group = ast.age_group

ORDER BY
    CASE
        WHEN qs.age_group = 'NA' THEN 999
        WHEN qs.age_group = '80+' THEN 1000
        ELSE CAST(SUBSTRING_INDEX(qs.age_group, '-', 1) AS UNSIGNED)
    END,
    qs.quarter;
