--Z_SQL_FORECAST_DETAIL
--VBA_SALESCUBE_FCT_WKLY.sql 2024-08-26_0031

--SALESCUBE_COMPONENTS/BASE_DEMAND.sql 2024-08-23_1431

WITH DMD AS(

--SALESCUBE_COMPONENTS/DMD.sql 2024-08-23_1427

	SELECT NULL AS "DocEntry", NULL AS "LineNum", im."ItemCode", im."Warehouse" AS "WhsCode", w1."WhsCode" AS "RcvWhs", im."DocDate", im."DocDate" AS "ShipDate", 
	(im."InQty"-im."OutQty") * -1 AS "Quantity", im."CardCode"
	FROM OINM im
	JOIN WTR1 w1 ON im."CreatedBy"=w1."DocEntry" AND im."DocLineNum"=w1."LineNum"
	WHERE im."DocDate" >= ADD_DAYS(CURRENT_DATE, -550) 
	AND im."Warehouse" IN('01') --From Warehouse
	AND w1."WhsCode" IN('TruckStock') --To Warehouse (ie Truck Stock)
	AND im."TransType"=67 
	UNION ALL
	SELECT
	"DocEntry", "LineNum", "ItemCode", '03' AS "WhsCode", 'SALE' AS "RcvWhs", "DocDate", "ShipDate", "Quantity", "BaseCard" AS "CardCode"
	FROM RDR1
	WHERE
	    "DocDate" >= ADD_DAYS(CURRENT_DATE, -550) 
	    --AND "WhsCode" IN('01') 
	    AND "Quantity" > 0 AND NOT ("LineStatus"='C' AND "TargetType" = -1) AND "LineStatus" IN ('O', 'C') AND "DropShip"='N' 

--SALESCUBE_COMPONENTS/DMD.sql

),
ORDER1 AS (
	SELECT
	COUNT(*) OVER () AS total_row_count,
	r1."DocEntry", r1."LineNum",
	ai."ItemCode" AS "AltItemCode", i."ItemCode" AS "OrderItemCode", COALESCE(ai."ItemCode",i."ItemCode") AS "ItemCode", 
	ai."PlaningSys" AS "AltPlaningSys", i."PlaningSys" AS "OrderPlaningSys", COALESCE(ai."PlaningSys",i."PlaningSys") AS "PlaningSys",
	ai."LeadTime" AS "AltLeadTime", i."LeadTime" AS "OrderLeadTime", COALESCE(ai."LeadTime",i."LeadTime") AS "LeadTime",	
	ai."OrdrIntrvl" AS "AltOrdrIntrvl", i."OrdrIntrvl" AS "OrderOrdrIntrvl", COALESCE(ai."OrdrIntrvl",i."OrdrIntrvl") AS "OrdrIntrvl",	
	ai."OrdrMulti" AS "AltOrdrMulti", i."OrdrMulti" AS "OrderOrdrMulti", COALESCE(ai."OrdrMulti",i."OrdrMulti") AS "OrdrMulti",
	acy."Name" AS "AltName", cy."Name" AS "OrderName", COALESCE(acy."Name",cy."Name") AS "Name",
 	a."Match", r1."Quantity" AS "OrderQuantity", CAST(CASE WHEN a."Match" IS NULL then "Quantity" ELSE 100/a."Match" * "Quantity" END AS INTEGER) AS "Quantity",
	r1."CardCode" AS "CustCardCode", ai."CardCode" AS "AltVendCode", i."CardCode" AS "OrderVendCode", COALESCE(ai."CardCode",i."CardCode") AS "VendCode",
	r1."WhsCode", r1."WhsCode" AS "ShipWhs", "DocDate", "ShipDate", a."Remarks", 	
	i."RuleCode", iw."MinOrder",
    ADD_MONTHS(TO_DATE(ADD_DAYS(CURRENT_DATE, -DAYOFWEEK(CURRENT_DATE))), -12) AS "YrStartDate",
    TO_DATE(ADD_DAYS(CURRENT_DATE, -DAYOFWEEK(CURRENT_DATE))) AS "YrEndDate"
	FROM DMD r1
	LEFT JOIN OITM i ON r1."ItemCode"=i."ItemCode"
	LEFT JOIN OITW iw ON r1."ItemCode"=iw."ItemCode" AND '03'=iw."WhsCode" 
	LEFT JOIN OCRD c ON r1."CardCode"=c."CardCode"
	LEFT JOIN OCYC cy ON cy."Code" = i."OrdrIntrvl" 
	LEFT JOIN OALI a ON r1."ItemCode"=a."OrigItem" AND i."PlaningSys"='N'
	LEFT JOIN OITM ai ON (a."AltItem"=ai."ItemCode" OR ai."ItemCode" IS NULL)  AND i."PlaningSys"='N'
	LEFT JOIN OCYC acy ON acy."Code" = ai."OrdrIntrvl"	
	WHERE i."LeadTime"<>0 AND i."LeadTime" IS NOT NULL AND cy."Name"<> 'NONSTOCK' AND NOT(i."PlaningSys"='N' AND ai."PlaningSys"='N')
)

--SALESCUBE_COMPONENTS/BASE_DEMAND.sql

,

FCT_WKLY AS(
SELECT
    r1."ItemCode",
    r1."WhsCode",
	CASE WHEN r1."Name"='NONSTOCK' THEN 0 ELSE CAST(SUM(CASE WHEN r1."DocDate" BETWEEN r1."YrStartDate" AND r1."YrEndDate" THEN r1."Quantity" ELSE 0 END)/52 AS INTEGER) END AS "WkFctQty"
FROM ORDER1 r1
GROUP BY r1."ItemCode", r1."WhsCode", r1."Name"
HAVING CASE WHEN r1."Name"='NONSTOCK' THEN 0 ELSE CAST(SUM(CASE WHEN r1."DocDate" BETWEEN r1."YrStartDate" AND r1."YrEndDate" THEN r1."Quantity" ELSE 0 END)/52 AS INTEGER) END<>0
),

----SALESCUBE/FORECAST

DateDiff AS (
    SELECT
        TO_VARCHAR(ADD_DAYS(CURRENT_DATE, - (DAYOFWEEK(CURRENT_DATE) - 2) - (0 * 7)), 'YYYYMMDD') AS MinDate,
        TO_VARCHAR(ADD_DAYS(CURRENT_DATE, (8 - DAYOFWEEK(CURRENT_DATE)) + (51 * 7)), 'YYYYMMDD') AS MaxDate,     
        TO_VARCHAR(
            FLOOR(DAYS_BETWEEN(
                TO_VARCHAR(ADD_DAYS(CURRENT_DATE, - (DAYOFWEEK(CURRENT_DATE) - 2) - (0 * 7)), 'YYYYMMDD'),
                TO_VARCHAR(ADD_DAYS(CURRENT_DATE, (8 - DAYOFWEEK(CURRENT_DATE)) + (51 * 7)), 'YYYYMMDD')
            ) / 7+1)
        ) || 'WKS ' || 
        TO_VARCHAR(ADD_DAYS(CURRENT_DATE, - (DAYOFWEEK(CURRENT_DATE) - 2) - (0 * 7)), 'YYYYMMDD') || '-' || 
        TO_VARCHAR(ADD_DAYS(CURRENT_DATE, (8 - DAYOFWEEK(CURRENT_DATE)) + (51 * 7)), 'YYYYMMDD') ||
        ' (' || TO_VARCHAR(CURRENT_TIMESTAMP, 'MM/DD/YYYY HH24:MI:SS AM') || ')' AS "Name"
    FROM DUMMY
),
FCT1 AS (
	SELECT F1.*
	FROM FCT1 F1
	Left JOIN OFCT f ON f."AbsID"=F1."AbsID"
),
FCT_VBA AS(	
SELECT 
    -- Total number of rows in the result set, repeated in every row
    COUNT(*) OVER () AS "TotalRows",
    (COUNT(*) OVER ())/52 AS "TotalItems",
    
    -- AbsID
    IFNULL(F1."AbsID",F."AbsID") AS "AbsID",

	-- LineID       
    F1."LineID" - 1 AS "FCT1_LineID",
	ROW_NUMBER() OVER (
	    PARTITION BY COALESCE(F1."AbsID", F."AbsID") 
	    ORDER BY 
	        CASE 
	            WHEN F1."LineID" IS NULL THEN 1 
	            ELSE 0 
	        END, 
	        F1."LineID"
	) - 1 AS "CALC_LineID",  
    
    -- Quantity	                   
    COALESCE(F1."Quantity", 0) AS FCT1_QTY,
    WF."WkFctQty" AS WF_QTY,    

	--Date      
    TO_CHAR("Date", 'YYYYMMDD') AS "FCT1_Date", 
    IFNULL(TO_VARCHAR(ADD_DAYS(CURRENT_DATE, GENERATED_PERIOD_START), 'YYYYMMDD'), TO_CHAR("Date", 'YYYYMMDD')) AS "Date",
     
    -- ItemCode
    COALESCE(WF."ItemCode", F1."ItemCode") AS "FCT1_ItemCode",     

	-- Warehouse
    COALESCE(WF."WhsCode", F1."WhsCode") AS "FCT1_WhsCode",
    
    MIN(COALESCE(F1."Quantity", 0)) OVER (PARTITION BY F."AbsID", COALESCE(WF."ItemCode", F1."ItemCode")) AS "MinItemFctQty",
    MAX(COALESCE(F1."Quantity", 0)) OVER (PARTITION BY F."AbsID", COALESCE(WF."ItemCode", F1."ItemCode")) AS "MaxItemFctQty",      
    "Code",
     'AX_' || 
    'ABS' || TO_VARCHAR(F."AbsID") || '_' ||
    "Code"|| '_' ||
    TO_VARCHAR(GREATEST("StartDate", ADD_DAYS(CURRENT_DATE, - (DAYOFWEEK(CURRENT_DATE) - 2) - (0 * 7))), 'YYYYMMDD') || '-' || 
    TO_VARCHAR(GREATEST("EndDate", ADD_DAYS(CURRENT_DATE, (8 - DAYOFWEEK(CURRENT_DATE)) + (51 * 7))), 'YYYYMMDD') || '_' || 
    TO_VARCHAR(CURRENT_TIMESTAMP, 'MMDD_HH24MI') || '_' || 
    'CORP' 
    --'CMP' || '_' ||  || '_' || 'AX'--This will be for the types for WT
    AS "Name",   
    -- Calculate and format the start of the week (Monday) for each generated period
    TO_VARCHAR(ADD_DAYS(CURRENT_DATE, GENERATED_PERIOD_START), 'YYYYMMDD') AS "WkMonday",    
    -- Calculate and format the end of the week (Sunday) for each generated period
    TO_VARCHAR(ADD_DAYS(CURRENT_DATE, GENERATED_PERIOD_START + 6), 'YYYYMMDD') AS "WkSunday",   
    -- Determine the earliest Monday across the generated series for each AbsID and repeat it in all rows
    TO_VARCHAR(MIN(ADD_DAYS(CURRENT_DATE, GENERATED_PERIOD_START)) OVER (PARTITION BY F."AbsID"), 'YYYYMMDD') AS "FctMonday",   
    -- Determine the latest Sunday across the generated series for each AbsID and repeat it in all rows
    TO_VARCHAR(MAX(ADD_DAYS(CURRENT_DATE, GENERATED_PERIOD_START + 6)) OVER (PARTITION BY F."AbsID"), 'YYYYMMDD') AS "FctSunday",
    'W' AS "View",
    i."CardCode"  
      
FROM FCT_WKLY WF
CROSS JOIN OFCT F
-- Generate a series of 7 periods starting on a Monday (calculated as 2 - DAYOFWEEK(CURRENT_DATE))
-- The third parameter determines the interval between each period (365 days in this case)
CROSS JOIN SERIES_GENERATE_INTEGER(7, 2 - DAYOFWEEK(CURRENT_DATE), 365)
FULL OUTER JOIN FCT1 F1 ON 
    TO_VARCHAR(F1."Date", 'YYYYMMDD') = TO_VARCHAR(ADD_DAYS(CURRENT_DATE, GENERATED_PERIOD_START), 'YYYYMMDD')
    AND (WF."ItemCode" = F1."ItemCode" OR F1."ItemCode" IS NULL OR WF."ItemCode" IS NULL)
    AND (WF."WhsCode" = F1."WhsCode" OR F1."WhsCode" IS NULL OR WF."WhsCode" IS NULL)
    AND F."AbsID"=F1."AbsID"
LEFT JOIN OITM i ON i."ItemCode" = COALESCE(WF."ItemCode", F1."ItemCode")    

WHERE 	COALESCE(F1."ItemCode", WF."ItemCode") IS NOT NULL 
		AND IFNULL(F."AbsID", F1."AbsID") = 7
		--AND COALESCE(F1."Quantity", 0) <> COALESCE(WF."WkFctQty", 0)
ORDER BY COALESCE(F."AbsID", F1."AbsID"), F1."LineID"
)
SELECT * FROM FCT_VBA
/*SELECT 
	'ParentKey' AS "ParentKey", 'LineNum' AS "LineNum", 'Quantity' AS "Quantity", 
	'ForecastedDay' AS "ForecastedDay", 'ItemNo' AS "ItemNo", 'Warehouse' AS "Warehouse" 
FROM DUMMY 
UNION ALL
SELECT     
	CAST("AbsID" AS VARCHAR) AS "Numerator", 
    CAST("LineID" AS VARCHAR) AS "LineNum", 
    CAST("WkFctQty" AS VARCHAR) AS "Quantity", 
    CAST("Date" AS VARCHAR) AS "Date", 
    "ItemCode" AS "ItemCode", 
    "WhsCode" AS "Warehouse"
FROM FCT_VBA*/
