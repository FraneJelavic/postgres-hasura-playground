workspace "PostgreSQL Hasura Playground" "Single-host lab for Hasura GraphQL backed by a Patroni-managed PostgreSQL HA cluster." {
    !identifiers hierarchical

    model {
        developer = person "Developer" "Starts the lab, uses the GraphQL API and console, inspects health, and exercises switchover and failover."
        dockerHost = softwareSystem "Docker Engine or Colima" "Runs every playground process and project-scoped named volume on one host."
        registries = softwareSystem "Public upstream registries" "Supply the pinned PostgreSQL, etcd, HAProxy, and Hasura images."

        playground = softwareSystem "PostgreSQL Hasura Playground" "Educational, single-host Hasura GraphQL environment backed by highly available PostgreSQL." {
            group "Three-member DCS quorum" {
                etcd1 = container "etcd 1" {
                    description "Voting Patroni distributed-configuration-store member."
                    technology "etcd 3.5.33"
                    tags "Redundant"
                }
                etcd2 = container "etcd 2" {
                    description "Voting Patroni distributed-configuration-store member."
                    technology "etcd 3.5.33"
                    tags "Redundant"
                }
                etcd3 = container "etcd 3" {
                    description "Voting Patroni distributed-configuration-store member."
                    technology "etcd 3.5.33"
                    tags "Redundant"
                }
            }

            group "PostgreSQL high availability" {
                haproxy = container "HAProxy" {
                    description "Stable PostgreSQL write endpoint; Patroni health checks route new connections only to the current primary."
                    technology "HAProxy 3.2.22"
                    tags "SingleInstance"
                }
                postgres1 = container "PostgreSQL + Patroni 1" {
                    description "Primary or asynchronous streaming replica; the role changes during switchover and failover."
                    technology "PostgreSQL 16.14 / Patroni 4.1.5"
                    tags "Redundant,Database"
                }
                postgres2 = container "PostgreSQL + Patroni 2" {
                    description "Primary or asynchronous streaming replica; the role changes during switchover and failover."
                    technology "PostgreSQL 16.14 / Patroni 4.1.5"
                    tags "Redundant,Database"
                }
                postgres3 = container "PostgreSQL + Patroni 3" {
                    description "Primary or asynchronous streaming replica; the role changes during switchover and failover."
                    technology "PostgreSQL 16.14 / Patroni 4.1.5"
                    tags "Redundant,Database"
                }
            }

            group "GraphQL API" {
                hasura = container "Hasura GraphQL Engine" {
                    description "Serves the authenticated GraphQL API and console, stores metadata separately, and accesses application data through HAProxy."
                    technology "Hasura GraphQL Engine 2.42.0"
                    tags "SingleInstance"
                }
            }

            group "One-shot initialization" {
                databaseInit = container "Database initializer" {
                    description "Idempotently creates the Hasura metadata and application roles and databases through the writable endpoint."
                    technology "Bash / psql 16.14"
                    tags "Initializer"
                }
                hasuraInit = container "Hasura project initializer" {
                    description "Idempotently deploys tracked metadata, the todos migration, and the seed through the Hasura API."
                    technology "Hasura CLI 2.42.0"
                    tags "Initializer"
                }
            }

            group "Project-scoped named volumes" {
                etcd1Volume = container "etcd1-data" {
                    description "Persistent etcd member data."
                    technology "Docker volume"
                    tags "Volume"
                }
                etcd2Volume = container "etcd2-data" {
                    description "Persistent etcd member data."
                    technology "Docker volume"
                    tags "Volume"
                }
                etcd3Volume = container "etcd3-data" {
                    description "Persistent etcd member data."
                    technology "Docker volume"
                    tags "Volume"
                }
                postgres1Volume = container "postgres1-data" {
                    description "Persistent PostgreSQL member data and WAL."
                    technology "Docker volume"
                    tags "Volume"
                }
                postgres2Volume = container "postgres2-data" {
                    description "Persistent PostgreSQL member data and WAL."
                    technology "Docker volume"
                    tags "Volume"
                }
                postgres3Volume = container "postgres3-data" {
                    description "Persistent PostgreSQL member data and WAL."
                    technology "Docker volume"
                    tags "Volume"
                }
            }

            hasura -> haproxy "Reads and writes application and metadata databases through the stable endpoint" "PostgreSQL" "Data"
            databaseInit -> haproxy "Creates roles and databases through the stable endpoint" "PostgreSQL" "Control"
            hasuraInit -> hasura "Deploys metadata, migrations, and seeds" "HTTP/JSON" "Control"

            haproxy -> postgres1 "Routes writes when primary" "PostgreSQL" "Data"
            haproxy -> postgres2 "Routes writes when primary" "PostgreSQL" "Data"
            haproxy -> postgres3 "Routes writes when primary" "PostgreSQL" "Data"

            postgres1 -> etcd1 "Reads and writes cluster state" "HTTP" "Control"
            postgres1 -> etcd2 "Reads and writes cluster state" "HTTP" "Control"
            postgres1 -> etcd3 "Reads and writes cluster state" "HTTP" "Control"
            postgres2 -> etcd1 "Reads and writes cluster state" "HTTP" "Control"
            postgres2 -> etcd2 "Reads and writes cluster state" "HTTP" "Control"
            postgres2 -> etcd3 "Reads and writes cluster state" "HTTP" "Control"
            postgres3 -> etcd1 "Reads and writes cluster state" "HTTP" "Control"
            postgres3 -> etcd2 "Reads and writes cluster state" "HTTP" "Control"
            postgres3 -> etcd3 "Reads and writes cluster state" "HTTP" "Control"

            postgres1 -> postgres2 "Streams WAL when postgres1 is primary" "PostgreSQL replication" "Replication"
            postgres1 -> postgres3 "Streams WAL when postgres1 is primary" "PostgreSQL replication" "Replication"
            postgres2 -> postgres1 "Streams WAL when postgres2 is primary" "PostgreSQL replication" "Replication"
            postgres2 -> postgres3 "Streams WAL when postgres2 is primary" "PostgreSQL replication" "Replication"
            postgres3 -> postgres1 "Streams WAL when postgres3 is primary" "PostgreSQL replication" "Replication"
            postgres3 -> postgres2 "Streams WAL when postgres3 is primary" "PostgreSQL replication" "Replication"

            etcd1 -> etcd1Volume "Persists member state" "Filesystem" "Persistence"
            etcd2 -> etcd2Volume "Persists member state" "Filesystem" "Persistence"
            etcd3 -> etcd3Volume "Persists member state" "Filesystem" "Persistence"
            postgres1 -> postgres1Volume "Persists data and WAL" "Filesystem" "Persistence"
            postgres2 -> postgres2Volume "Persists data and WAL" "Filesystem" "Persistence"
            postgres3 -> postgres3Volume "Persists data and WAL" "Filesystem" "Persistence"
        }

        developer -> playground "Uses make targets and localhost-only endpoints"
        playground -> dockerHost "Runs entirely on" "Docker Compose"
        registries -> dockerHost "Provide pinned public images" "HTTPS"

        developer -> playground.hasura "Uses the console and authenticated GraphQL API" "HTTP/JSON" "GraphQL"
        developer -> playground.haproxy "Uses the stable SQL endpoint and observes routing statistics" "PostgreSQL / HTTP"
        developer -> playground.postgres1 "Inspects Patroni health and cluster state" "HTTP"
        developer -> playground.postgres2 "Inspects Patroni health and cluster state" "HTTP"
        developer -> playground.postgres3 "Inspects Patroni health and cluster state" "HTTP"
    }

    views {
        systemContext playground "context" {
            include *
            include registries
            autolayout lr
            title "PostgreSQL Hasura Playground - System Context"
            description "A developer runs and observes a local Hasura GraphQL and PostgreSQL HA lab on one Docker Engine or Colima host."
        }

        container playground "containers" {
            include *
            autolayout tb
            title "PostgreSQL Hasura Playground - Containers"
            description "Green elements are redundant processes; orange elements remain single-instance. All processes and named volumes share one host."
        }

        styles {
            element "Element" {
                color #ffffff
                fontSize 20
            }
            element "Person" {
                shape person
                background #08427b
            }
            element "Software System" {
                background #1168bd
            }
            element "Container" {
                background #438dd5
            }
            element "Redundant" {
                background #2e7d32
            }
            element "SingleInstance" {
                background #ef6c00
            }
            element "Initializer" {
                background #546e7a
            }
            element "Volume" {
                shape cylinder
                background #5d4037
            }
            element "Database" {
                shape cylinder
            }
            element "Group" {
                color #263238
                stroke #607d8b
            }
            relationship "Relationship" {
                color #455a64
                fontSize 16
            }
            relationship "Control" {
                dashed true
                color #616161
            }
            relationship "GraphQL" {
                color #6a1b9a
                thickness 4
            }
            relationship "Replication" {
                color #2e7d32
                dashed true
            }
            relationship "Persistence" {
                color #5d4037
            }
        }
    }

    configuration {
        scope softwaresystem
    }
}
