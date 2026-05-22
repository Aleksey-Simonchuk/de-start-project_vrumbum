-- Этап 1. Создание и заполнение БД

/* создаём схему сырых данных из старой бд*/

CREATE SCHEMA IF NOT EXISTS raw_data;

/* создаём копию таблицы с сырыми данными из файла старой бд*/

CREATE TABLE IF NOT EXISTS raw_data.sales (
	id INTEGER,
	auto TEXT,
	gasoline_consumption NUMERIC(3, 1),
	price NUMERIC,
	date DATE,
	person_name TEXT,
	phone TEXT,
	discount INTEGER,
	brand_origin TEXT
);

/* заполняем таблицу значениями через терминал  с помощью psql*/

/* \copy raw_data.sales(id, auto, gasoline_consumption, price, date, person_name, phone, discount, brand_origin)
FROM '/home/sas/Dev/cars.csv' CSV HEADER NULL 'null';*/

/* обнаружили пропуски в атрибуте 'brand_origin', проверка показала, что все авто - porsche,
 * а все знают, что это немецкий бренд, обогатим данные*/

SELECT auto
FROM raw_data.sales
WHERE brand_origin IS NULL;

/* исправляем brand_origin у porsche*/

UPDATE raw_data.sales
SET brand_origin = 'Germany'
WHERE brand_origin IS NULL;

/* создаём схему в основной базе данных*/

CREATE SCHEMA IF NOT EXISTS car_shop;

/* создаём таблицу цветов*/

CREATE TABLE IF NOT EXISTS car_shop.colors (
	id SERIAL PRIMARY KEY, /* всё согласно условию. т.е. ТЗ*/
	name VARCHAR(25) NOT NULL UNIQUE /*цвета это текст, небольшой запас по длине для составных типа "серебристо-зеленый"*/
);

/* заполняем данными*/

INSERT INTO car_shop.colors (name)
SELECT DISTINCT split_part(auto, ', ', 2) AS color
FROM raw_data.sales;

/* создаём таблицу стран*/

CREATE TABLE IF NOT EXISTS car_shop.brand_origin (
	id SERIAL PRIMARY KEY,
	name VARCHAR(20) NOT NULL UNIQUE /* страна происхождения бренда это текст*/
);

/* заполняем данными*/

INSERT INTO car_shop.brand_origin (name)
SELECT DISTINCT brand_origin
FROM raw_data.sales
WHERE brand_origin IS NOT NULL;

/* создаём таблицу брендов*/

CREATE TABLE IF NOT EXISTS car_shop.brands (
	id SERIAL PRIMARY KEY,
	name VARCHAR(20) NOT NULL UNIQUE /* в названии бренда могут быть и цифры, и буквы, поэтому выбираем varchar*/
);

/* заполняем данными*/

INSERT INTO car_shop.brands (name)
SELECT DISTINCT split_part(auto, ' ', 1)
FROM raw_data.sales;

/* создаём таблицу автомобилей*/

CREATE TABLE IF NOT EXISTS car_shop.models (
	id SERIAL PRIMARY KEY, /* по ТЗ*/ 
	name VARCHAR(20) NOT NULL UNIQUE, /*есть текст и цифры в названии, основной атрибут, определяющий уникальность*/
	gasoline_consumption NUMERIC(3,1) /* грузовые авто не продаём и заявленной точности и количества цифр достаточно*/
);

/* заполняем данными*/

INSERT INTO car_shop.models (name, gasoline_consumption)
SELECT
	DISTINCT ltrim(REPLACE(split_part(auto, ', ', 1), split_part(auto, ' ', 1), '')),
	gasoline_consumption::NUMERIC(3, 1)
FROM raw_data.sales;

/*создаём таблицу клиентов*/

CREATE TABLE IF NOT EXISTS car_shop.clients (
	id SERIAL PRIMARY KEY, /* по ТЗ*/
	first_name VARCHAR(20) NOT NULL, /* имя это текст*/
	last_name VARCHAR(20) NOT NULL, /* фамилия это текст*/
	phone VARCHAR(30) UNIQUE /* телефон это натуральный первичный ключ, для арифметики не нужен, поэтому текст*/
);

/* заполняем данными*/

INSERT INTO car_shop.clients (phone, first_name, last_name)
SELECT
	DISTINCT phone,
	split_part(person_name, ' ', 1) AS first_name,
	split_part(person_name, ' ', 2) AS last_name
FROM raw_data.sales;

/* создаём таблицу сделок по покупке автомобилей*/

CREATE TABLE IF NOT EXISTS car_shop.invoices (
	id SERIAL PRIMARY KEY, /* по ТЗ*/
	brand_id INTEGER REFERENCES car_shop.brands, /* id бренда*/
	model_id INTEGER REFERENCES car_shop.models, /* связь с моделями напрямую*/
	color_id INTEGER REFERENCES car_shop.colors,/* связь с цветом напрямую*/
	price NUMERIC(9,2) NOT NULL CHECK (price > 0), /*цена может содержать только сотые
	и не может быть больше семизначной суммы.
	У numeric повышенная точность при работе с дробными числами,
	поэтому при операциях c этим типом данных,
	дробные числа не потеряются*/
	discount INTEGER DEFAULT 0 CHECK (discount >= 0), /* целое число, но при желании можно перевести в доли и сделать numeric*/
	billing_date DATE NOT NULL DEFAULT CURRENT_DATE, /* дата продажи, по умолчанию ставим текущую дату заполнения*/
	customer_id INTEGER REFERENCES car_shop.clients, /* связь со справочником клиентов напрямую*/
	country_id INTEGER REFERENCES car_shop.brand_origin /* связь со справочником стран*/
);

/* заполняем данными*/

INSERT INTO car_shop.invoices (
	brand_id,
	model_id,
	color_id,
	price,
	discount,
	billing_date,
	customer_id,
	country_id
)
SELECT
	b.id,
	m.id,
	c.id,
	raw.price,
	raw.discount,
	raw.date,
	cl.id,
	bo.id
FROM raw_data.sales raw
LEFT JOIN car_shop.brands b
ON split_part(raw.auto, ' ', 1) = b.name
LEFT JOIN car_shop.models m
ON ltrim(REPLACE(split_part(raw.auto, ', ', 1), split_part(raw.auto, ' ', 1), '')) = m.name
LEFT JOIN car_shop.colors c
ON split_part(raw.auto, ', ', 2) = c.name
LEFT JOIN car_shop.clients cl
ON raw.phone = cl.phone
LEFT JOIN car_shop.brand_origin bo
ON raw.brand_origin = bo.name
ORDER BY raw.id;

--/* проверка отдельных строк таблиц на схожесть с возможностью менять номера строк в where*/

SELECT * FROM raw_data.sales;

SELECT
	i.id,
	b.name || ' ' || m.name || ' ' || c.name,
	m.gasoline_consumption,
	i.price,
	i.billing_date,
	cli.first_name || ' ' || cli.last_name,
	cli.phone,
	i.discount,
	bo.name
FROM car_shop.invoices i
LEFT JOIN car_shop.brands b
ON i.brand_id = b.id
LEFT JOIN car_shop.models m
ON i.model_id = m.id
LEFT JOIN car_shop.colors c
ON i.color_id = c.id
LEFT JOIN car_shop.clients cli
ON i.customer_id = cli.id
LEFT JOIN car_shop.brand_origin bo
ON i.country_id = bo.id
WHERE i.id = 234
UNION
SELECT *
FROM raw_data.sales
WHERE id = 234;

-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.

SELECT
	100 - count(m.gasoline_consumption) / count(i.id)::NUMERIC * 100 AS nulls_percentage_gasoline_consumption
FROM car_shop.invoices i
LEFT JOIN car_shop.models m
ON i.model_id = m.id;

---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.

SELECT 
	b.name AS brand_name,
	EXTRACT(YEAR FROM i.billing_date) AS year,
	avg(i.price)::numeric(9,2) AS price_avg
FROM car_shop.invoices i 
LEFT JOIN car_shop.brands b
ON i.brand_id = b.id
GROUP BY
	brand_name,
	year
ORDER BY
	b.name;

---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.

SELECT
	EXTRACT(MONTH FROM billing_date) AS month,
	EXTRACT(YEAR FROM billing_date) AS year,
	avg(price)::NUMERIC(9, 2) AS price_avg
FROM car_shop.invoices
WHERE EXTRACT(YEAR FROM billing_date) = 2022
GROUP BY
	month,
	year;

---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.

SELECT
	cl.first_name || ' ' || cl.last_name AS person,
	string_agg(b.name || ' ' || m.name, ', ') AS cars
FROM car_shop.invoices i
LEFT JOIN car_shop.brands b
ON i.brand_id = b.id
LEFT JOIN car_shop.models m
ON i.model_id = m.id
LEFT JOIN car_shop.clients cl
ON i.customer_id = cl.id
GROUP BY cl.first_name || ' ' || cl.last_name
ORDER BY person;

---- Задание 5. Напишите запрос, который вернёт самую большую и самую маленькую цену продажи автомобиля с разбивкой по стране без учёта скидки.

SELECT
	b.name AS brand_origin,
	max(i.price / (1 - i.discount / 100)) AS price_max,
	min(i.price / (1 - i.discount / 100)) AS price_min
FROM car_shop.invoices i
LEFT JOIN car_shop.brands b
ON i.brand_id = b.id
GROUP BY b.name;

---- Задание 6. Напишите запрос, который покажет количество всех пользователей из США.

SELECT count(phone) AS persons_from_usa_count
FROM car_shop.clients
WHERE phone LIKE '+1%';
