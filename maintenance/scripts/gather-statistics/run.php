#!/usr/bin/php
<?php
	require_once(__DIR__ . '/functions.php');

	if (empty($config['influx']['host']) || empty($config['bind']['slaves'])) { die(0); }

	$client = new InfluxDB\Client($config['influx']['host'], $config['influx']['port']);

	$database = $client->selectDB($config['influx']['db']);
	if (!$database->exists()) { $database->create(); }

	function parseStats($server, $xml, $time = NULL) {
		$points = [];

		echo 'Parsing statistics for server: ', $server, "\n";

		if ($time == NULL) {
			$time = strtotime((string)$xml->xpath('/statistics/server/current-time')[0]);
		}

		// Global Statistics
		$query = (int)$xml->xpath('/statistics/server/counters[@type="opcode"]/counter[@name="QUERY"]')[0][0];
		$points[] = new InfluxDB\Point('opcode_query', $query, ['host' => $server], [], $time);

		foreach ($xml->xpath('/statistics/server/counters[@type="qtype"]/counter') as $counter) {
			$type = (string)$counter['name'];
			$value = (int)$counter;
			$points[] = new InfluxDB\Point('qtype', $value, ['host' => $server, 'qtype' => $type], [], $time);
		}

		// Per-Zone Statistics
		foreach ($xml->xpath('/statistics/views/view[@name="_default"]/zones/zone') as $zone) {
			$zoneName = strtolower((string)$zone['name']);

			foreach ($zone->xpath('counters[@type="qtype"]/counter') as $counter) {
				$type = (string)$counter['name'];
				$value = (int)$counter;
				$points[] = new InfluxDB\Point('zone_qtype', $value, ['host' => $server, 'qtype' => $type, 'zone' => $zoneName], [], $time);
			}
		}

		return $points;
	}

	echo 'Begin statistics.', "\n";
	// Grab all stats
	$data = [];
	foreach (explode(',', $config['bind']['slaves']) as $slave) {
		$slave = trim($slave);
		$slave = explode('=', $slave);

		$name = $slave[0];
		$host = $slave[1];

		$data[$name] = @file_get_contents('http://' . $host . ':8080/');
	}

	// Parse stats into database.
	$time = time();
	foreach ($data as $name => $stats) {
		if (!empty($stats)) {
			$xml = simplexml_load_string($stats);

			$points = parseStats($name, $xml, $time);
			$result = $database->writePoints($points, InfluxDB\Database::PRECISION_SECONDS);
		}
	}
	echo 'End statistics.', "\n";
