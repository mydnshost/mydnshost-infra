#!/usr/bin/php
<?php
	require_once(__DIR__ . '/functions.php');
	$api = new MyDNSHostAPI($config['mydnshost']['api']);
	$api->setAuthDomainKey($config['mydnshost']['domain'], $config['mydnshost']['domain_key']);

	// Get the list of RRs we cycle through
	$rrs = explode(',', $config['mydnshost']['rrnames']);
	// Get the test IDs we need to update.
	$tests = explode(',', $config['statuscake']['testids']);

	// Get the current "active" RRNAME.
	// This is denoted by the value of the "active" TXT record.
	//
	// If there isn't an "active" TXT record, create it.
	$active = $api->getDomainRecordsByName($config['mydnshost']['domain'], 'active');
	if (!isset($active[0])) {
		$active = ['name' => 'active', 'type' => 'TXT', 'content' => $rrs[0]];
		$api->setDomainRecords($config['mydnshost']['domain'], ['records' => [$active]]);
	} else {
		$active = $active[0];
	}

	// Find the "active" RRNAME in our list of RRNAMES.
	// if it is not there, assume the first one.
	$oldActivePos = array_search($active['content'], $rrs);
	if ($oldActivePos === FALSE) { $oldActivePos = 0; }
	// Find the next one to use
	$newActivePos = ($oldActivePos + 1) % count($rrs);

	// Find the actual record we need to chagne (the new active RRNAME).
	// Create it if it does not exist.
	$activerr = $api->getDomainRecordsByName($config['mydnshost']['domain'], $rrs[$newActivePos]);
	if (!isset($activerr[0])) {
		$activerr = ['name' => $rrs[$newActivePos], 'type' => 'A', 'content' => '127.0.0.1'];
		echo 'Create Missing ActiveRR', "\n";

		$activerr = $api->setDomainRecords($config['mydnshost']['domain'], ['records' => [$activerr]]);
		$activerr = $activerr['response']['changed']['0'];
	} else {
		$activerr = $activerr[0];
	}

	// Create a new value
	// $newContent = sprintf('127.%d.%d.%d', random_int(0, 255), random_int(0, 255), random_int(0, 255));
	$newContent = date('127.n.j.G'); // 127.month.day.hour

	echo 'Setting activerr (', $rrs[$newActivePos], ') to ', $newContent, "\n";

	// Update 'active' to point at the new activerr and the activerr with the new content.
	$api->setDomainRecords($config['mydnshost']['domain'], ['records' => [['id' => $active['id'], 'content' => $rrs[$newActivePos]], ['id' => $activerr['id'], 'content' => $newContent]]]);

	// Allow slaves time to update.
	sleep(30);

	// Update statuscake
	$headers = array('API' => $config['statuscake']['apikey'], 'Username' => $config['statuscake']['username']);
	$data = ['TestID' => '0', 'DNSIP' => $newContent, 'WebsiteURL' => sprintf('%s.%s', $rrs[$newActivePos], $config['mydnshost']['domain'])];

	foreach ($tests as $testid) {
		$data['TestID'] = $testid;
		Requests::put('https://app.statuscake.com/API/Tests/Update', $headers, $data);

		echo 'Updated test ', $testid, ' to check ', $data['WebsiteURL'], ' is ', $data['DNSIP'], "\n";
	}

	// Done.
