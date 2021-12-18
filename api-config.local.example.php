<?php
	$config['hooks']['bind']['enabled'] = 'true';
	$config['hooks']['bind']['catalogZoneFile'] = '/bind/catalog.db';
	$config['hooks']['bind']['catalogZoneName'] = 'catalog.invalid';
	$config['hooks']['bind']['zonedir'] = '/bind/zones';
	$config['hooks']['bind']['keydir'] = '/bind/keys';
	$config['hooks']['bind']['slaveServers'] = ['10.0.0.1', '10.0.0.2', '10.0.0.3'];

	$config['defaultRecords'] = [];
	$config['defaultRecords'][] = ['name' => '', 'type' => 'NS', 'content' => 'ns1.mydnshost.co.uk'];
	$config['defaultRecords'][] = ['name' => '', 'type' => 'NS', 'content' => 'ns2.mydnshost.co.uk'];
	$config['defaultRecords'][] = ['name' => '', 'type' => 'NS', 'content' => 'ns3.mydnshost.co.uk'];
	$config['defaultRecords'][] = ['name' => '', 'type' => 'NS', 'content' => 'ns4.mydnshost.co.uk'];

	$config['defaultSOA'] = ['primaryNS' => 'ns1.mydnshost.co.uk.'];
