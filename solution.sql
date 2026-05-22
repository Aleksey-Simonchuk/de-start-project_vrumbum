-- Этап 1. Создание и заполнение БД

/* создаём схему сырых данных из старой бд*/

CREATE SCHEMA IF NOT EXISTS raw_data;

/* создаём копию таблицы с сырыми данными из файла старой бд*/

CREATE TABLE IF NOT EXISTS raw_data.sales (
	id INTEGER,
	auto TEXT,
	gasoline_consumption VARCHAR,
	price NUMERIC,
	date DATE,
	person_name TEXT,
	phone TEXT,
	discount INTEGER,
	brand_origin TEXT
);

/* заполняем таблицу значениями через терминал  спомощью psql*/

/* \copy raw_data.sales(id, auto, gasoline_consumption, price, date, person_name, phone, discount, brand_origin)
FROM '/home/sas/Dev/cars.csv' CSV HEADER;*/

/* избавляемся от текстовых данных в атрибуте расхода топлива и заменяем на NULL*/

UPDATE raw_data.sales
SET gasoline_consumption = NULL
WHERE gasoline_consumption = 'null';

/* обнаружили 'null' в атрибуте 'brand_origin', проверка показала, что все авто - porsche,
 * а все знают, что это немецкий бренд, обогатим данные в новой схеме бд,-
 * пусть сырые будут в оригинале для истории*/

SELECT auto
FROM raw_data.sales
WHERE brand_origin = 'null';

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

/* создаём таблицу автомобилей*/

CREATE TABLE IF NOT EXISTS car_shop.cars (
	id SERIAL PRIMARY KEY, /* по ТЗ*/ 
	brand VARCHAR(20) NOT NULL, /* в названии бренда могут быть и цифры, и буквы, поэтому выбираем varchar*/
	model VARCHAR(20) NOT NULL UNIQUE, /*есть текст и цифры в названии, основной атрибут, определяющий уникальность*/
	gasoline_consumption NUMERIC(3,1), /* грузовые авто не продаём и заявленной точности и количества цифр достаточно*/
	brand_origin VARCHAR(20) NOT NULL /* страна происхождения бренда это текст*/
);

/* заполняем данными*/

INSERT INTO car_shop.cars (model, brand, gasoline_consumption, brand_origin)
SELECT
	DISTINCT ltrim(REPLACE(split_part(auto, ', ', 1), split_part(auto, ' ', 1), ''))  AS model,
	split_part(auto, ' ', 1) AS brand,
	gasoline_consumption::NUMERIC(3, 1),
	brand_origin
FROM raw_data.sales;

/* исправляем brand_origin у porsche*/

UPDATE car_shop.cars
SET brand_origin = 'Germany'
WHERE brand_origin = 'null';

/* создаём таблицу возможных расцветок автомобилей*/

CREATE TABLE IF NOT EXISTS car_shop.cars_colors (
	id SERIAL PRIMARY KEY, /* по ТЗ. атрибут определяющий полную уникальность авто*/
	car_id INTEGER REFERENCES car_shop.cars, /* модель*/
	color_id INTEGER REFERENCES car_shop.colors /* цвет*/
);

/* заполняем данными*/

INSERT INTO car_shop.cars_colors (car_id, color_id)
SELECT
	car_id,
	color_id
FROM
	generate_series(1, 19) AS car_id,
	generate_series(1, 8) AS color_id;

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
	cars_colors_id INTEGER REFERENCES car_shop.cars_colors, /* уникальный id комплектации авто*/
	car_id INTEGER REFERENCES car_shop.cars, /* связь с моделями напрямую*/
	color_id INTEGER REFERENCES car_shop.colors,/* связь с цветом напрямую*/
	price NUMERIC(9,2) NOT NULL CHECK (price > 0), /*цена может содержать только сотые
	и не может быть больше семизначной суммы.
	У numeric повышенная точность при работе с дробными числами,
	поэтому при операциях c этим типом данных,
	дробные числа не потеряются*/
	discount INTEGER DEFAULT 0 CHECK (discount >= 0), /* целое число, но при желании можно перевести в доли и сделать numeric*/
	billing_date DATE NOT NULL DEFAULT CURRENT_DATE, /* дата продажи, по умолчанию ставим текущую дату заполнения*/
	customer_id INTEGER REFERENCES car_shop.clients /* связь со справочником клиентов напрямую*/
);

/* заполняем данными*/

INSERT INTO car_shop.invoices (
	cars_colors_id,
	car_id,
	color_id,
	price,
	discount,
	billing_date,
	customer_id
)
SELECT
	cc.*,
	raw.price,
	raw.discount,
	raw.date,
	cli.id
FROM raw_data.sales raw
LEFT JOIN car_shop.colors cl 
ON split_part(raw.auto, ', ', 2) = cl.name
LEFT JOIN car_shop.cars cr
ON ltrim(REPLACE(split_part(raw.auto, ', ', 1), split_part(raw.auto, ' ', 1), '')) = cr.model
LEFT JOIN car_shop.cars_colors cc
ON cl.id = cc.color_id AND cr.id = cc.car_id
LEFT JOIN car_shop.clients cli
ON raw.phone = cli.phone
ORDER BY raw.id;

--/* проверка отдельных строк таблиц на схожесть с возможностью менять номера строк в where*/

SELECT
	i.id,
	c.model,
	c.gasoline_consumption::varchar,
	i.price,
	i.billing_date,
	cli.last_name,
	cli.phone,
	i.discount,
	c.brand_origin
FROM car_shop.invoices i
LEFT JOIN car_shop.cars c
ON i.car_id = c.id
LEFT JOIN car_shop.clients cli
ON i.customer_id = cli.id
WHERE i.id = 234
UNION
SELECT *
FROM raw_data.sales
WHERE id = 234;

-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.

SELECT
	100 - count(c.gasoline_consumption) / count(i.id)::NUMERIC * 100 AS nulls_percentage_gasoline_consumption
FROM car_shop.invoices i
LEFT JOIN car_shop.cars c
ON i.car_id = c.id;

---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.

SELECT 
	c.brand AS brand_name,
	EXTRACT(YEAR FROM i.billing_date) AS year,
	avg(i.price)::numeric(9,2) AS price_avg
FROM car_shop.invoices i 
LEFT JOIN car_shop.cars c
ON i.car_id = c.id
GROUP BY
	brand_name,
	year
ORDER BY
	c.brand;

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
	string_agg(cr.brand || ' ' || cr.model, ', ') AS cars
FROM car_shop.invoices i
LEFT JOIN car_shop.cars cr
ON i.car_id = cr.id
LEFT JOIN car_shop.clients cl
ON i.customer_id = cl.id
GROUP BY cl.first_name || ' ' || cl.last_name
ORDER BY person;

---- Задание 5. Напишите запрос, который вернёт самую большую и самую маленькую цену продажи автомобиля с разбивкой по стране без учёта скидки.

SELECT
	c.brand_origin AS brand_origin,
	max(i.price / (1 - i.discount / 100)) AS price_max,
	min(i.price / (1 - i.discount / 100)) AS price_min
FROM car_shop.invoices i
LEFT JOIN car_shop.cars c
ON i.car_id = c.id
GROUP BY c.brand_origin;

---- Задание 6. Напишите запрос, который покажет количество всех пользователей из США.

SELECT count(phone) AS persons_from_usa_count
FROM car_shop.clients
WHERE phone LIKE '+1%';
