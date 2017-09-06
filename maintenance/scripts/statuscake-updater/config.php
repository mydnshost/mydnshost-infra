<?php
	$config['mydnshost']['api'] = getEnvOrDefault('API_URL', 'https://api.mydnshost.co.uk/');
	$config['mydnshost']['domain'] = getEnvOrDefault('API_DOMAIN', 'test.example.org');
	$config['mydnshost']['rrnames'] = getEnvOrDefault('API_RRNAMES', 'foobar,bazqux');
	$config['mydnshost']['domain_key'] = getEnvOrDefault('API_DOMAINKEY', 'SomeKey');

	$config['statuscake']['username'] = getEnvOrDefault('STATUSCAKE_USER', 'SomeUser');
	$config['statuscake']['apikey'] = getEnvOrDefault('STATUSCAKE_APIKEY', 'SomeKey');

	$config['statuscake']['testids'] = getEnvOrDefault('STATUSCAKE_TESTIDS', '12345,67890');

	if (file_exists(dirname(__FILE__) . '/config.local.php')) {
		include(dirname(__FILE__) . '/config.local.php');
	}
