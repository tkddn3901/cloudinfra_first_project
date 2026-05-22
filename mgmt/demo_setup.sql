-- demo_congestion 테이블 생성 및 시나리오 데이터 초기화
-- 실행: psql "postgresql://scott:tiger@10.0.3.158/scott_db" -f demo_setup.sql

CREATE TABLE IF NOT EXISTS demo_congestion (
    tzon   integer      NOT NULL,
    sgg_nm varchar(20)  NOT NULL,
    cgst   numeric(6,2) NOT NULL,
    PRIMARY KEY (tzon, sgg_nm)
);

-- 기본 시나리오 데이터 (tzon = minute // 5, 0~11)
-- 스케일링 기준: cgst 0~10 → 0대(한적) / 11~60 → 1대(원활) / 61~ → 2대(혼잡)
INSERT INTO demo_congestion (tzon, sgg_nm, cgst) VALUES
    (0,  '강남구',  5.0), (0,  '은평구',  3.0),  -- 한적 → 0대
    (1,  '강남구', 45.0), (1,  '은평구',  8.0),  -- 원활/한적 → 1대/0대
    (2,  '강남구', 75.0), (2,  '은평구', 70.0),  -- 혼잡 → 2대
    (3,  '강남구', 80.0), (3,  '은평구', 75.0),  -- 혼잡 → 2대 (로드밸런싱 시연)
    (4,  '강남구', 40.0), (4,  '은평구', 45.0),  -- 원활 → 1대
    (5,  '강남구',  5.0), (5,  '은평구',  5.0),  -- 한적 → 0대
    (6,  '강남구',  8.0), (6,  '은평구',  7.0),  -- 한적 → 0대
    (7,  '강남구', 55.0), (7,  '은평구', 50.0),  -- 원활 → 1대
    (8,  '강남구', 90.0), (8,  '은평구', 85.0),  -- 혼잡 → 2대
    (9,  '강남구', 30.0), (9,  '은평구', 35.0),  -- 원활 → 1대
    (10, '강남구',  5.0), (10, '은평구',  6.0),  -- 한적 → 0대
    (11, '강남구', 60.0), (11, '은평구', 55.0)   -- 원활 → 1대
ON CONFLICT (tzon, sgg_nm) DO UPDATE SET cgst = EXCLUDED.cgst;

SELECT tzon, sgg_nm, cgst,
    CASE WHEN cgst <= 10 THEN '한적(0대)'
         WHEN cgst <= 60 THEN '원활(1대)'
         ELSE '혼잡(2대)' END AS 판단
FROM demo_congestion
ORDER BY tzon, sgg_nm;
