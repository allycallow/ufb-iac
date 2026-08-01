{
  "name": "debezium-postgres-outbox-source",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "plugin.name": "pgoutput",
    "database.hostname": "${db_host}",
    "database.port": "5432",
    "database.dbname": "${db_name}",
    "database.user": "debezium",
    "database.password": "$${secretsmanager:${urlencode(debezium_secret_arn)}:password}",
    "topic.prefix": "ufb-outbox",
    "slot.name": "debezium_outbox",
    "publication.name": "debezium_outbox_publication",
    "publication.autocreate.mode": "disabled",
    "table.include.list": "public.outbox_event",

    "transforms": "outbox",
    "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
    "transforms.outbox.route.by.field": "aggregatetype",
    "transforms.outbox.route.topic.replacement": "ufb.$${routedByValue}",
    "transforms.outbox.table.expand.json.payload": "true",
    "transforms.outbox.route.tombstone.on.empty.payload": "true",

    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",

    "errors.tolerance": "all",
    "errors.log.enable": "true"
  }
}
