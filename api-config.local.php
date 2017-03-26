<?php
	$config['hooks']['bind']['enabled'] = 'true';
	$config['hooks']['bind']['catalogZoneFile'] = '/bind/catalog.db';
	$config['hooks']['bind']['catalogZoneName'] = 'catalog.invalid';
	$config['hooks']['bind']['zonedir'] = '/bind/zones';

	$config['hooks']['bind']['addZoneCommand'] = 'chmod a+rwx %2$s;';
	$config['hooks']['bind']['reloadZoneCommand'] = 'chmod a+rwx %2$s;';
	$config['hooks']['bind']['delZoneCommand'] = '/bin/true';
