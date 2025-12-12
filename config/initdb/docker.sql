-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: database:3306
-- Generation Time: Oct 17, 2024 at 11:54 AM
-- Server version: 10.6.19-MariaDB-ubu2004
-- PHP Version: 8.2.24

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `docker`
--

-- --------------------------------------------------------

--
-- Table structure for table `mp_page404`
--

CREATE TABLE `mp_page404` (
  `p404_id` int(11) NOT NULL,
  `p404_http_referer` mediumtext NOT NULL,
  `p404_request_uri` mediumtext NOT NULL,
  `p404_ip` varchar(200) NOT NULL,
  `p404_count` int(11) NOT NULL DEFAULT 1,
  `p404_create` bigint(20) NOT NULL,
  `p404_update` bigint(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `mp_page404`
--

INSERT INTO `mp_page404` (`p404_id`, `p404_http_referer`, `p404_request_uri`, `p404_ip`, `p404_count`, `p404_create`, `p404_update`) VALUES
(2, 'NULL', '/myallphp/install/?page=req', '127.0.0.1', 1, 1729165821, 1729165821);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `mp_page404`
--
ALTER TABLE `mp_page404`
  ADD PRIMARY KEY (`p404_id`),
  ADD KEY `p404_ip` (`p404_ip`),
  ADD KEY `p404_request_uri` (`p404_request_uri`(250)),
  ADD KEY `p404_http_referer` (`p404_http_referer`(250));

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `mp_page404`
--
ALTER TABLE `mp_page404`
  MODIFY `p404_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
