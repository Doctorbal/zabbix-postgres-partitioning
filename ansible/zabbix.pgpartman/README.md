# README #

This ansible role configures the pg_partman on PostgreSQL version 11 for a Debian OS Distro.

Please review the comment notes in the [defaults/main.yml](defaults/main.yml) file!

## Dependencies

Tested on...
* Debian 8 (jessie) or 9 (stretch)
* PostgreSQL v11
* [ANXS postgresql ansible role](https://github.com/ANXS/postgresql) -  ensure you have PostgreSQL v11 Support

## Example playbook

`zabbix-database.yml`
```
- hosts: zabbix-database
  gather_facts: true
  become: yes
  roles:
    - { role: ANXS.postgresql, tags: [ 'postgresql' ] }
    - { role: zabbix.pgpartman, tags: [ 'pgpartman' ] }
```

## Running the playbook

```
ansible-playbook zabbix-database.yml -l <ZABBIX_DB_FQDN_OR_IP> -u <USERNAME>
```
