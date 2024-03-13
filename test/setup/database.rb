case ENV['TEST_DB']
when 'mysql'
  db_config_mysql = YAML::load(File.open(File.expand_path('../database.yml', __FILE__))).merge({
    adapter: 'mysql2',
    username: 'root'
  })
  db_config_mysql_admin = db_config_mysql.merge({database: 'information_schema'})
  ActiveRecord::Base.establish_connection(db_config_mysql_admin)
  ActiveRecord::Base.connection.drop_database(db_config_mysql["database"])
  ActiveRecord::Base.connection.create_database(db_config_mysql["database"])
  ActiveRecord::Base.establish_connection(db_config_mysql)
when 'postgresql'
  db_config_postgres       = YAML::load(File.open(File.expand_path('../database.yml', __FILE__))).merge({
    adapter: 'postgresql'
  })
  db_config_postgres_admin = db_config_postgres.merge({database: 'postgres', schema_search_path: 'public'})
  ActiveRecord::Base.establish_connection(db_config_postgres_admin)
  ActiveRecord::Base.connection.drop_database(db_config_postgres["database"])
  ActiveRecord::Base.connection.create_database(db_config_postgres["database"])
  ActiveRecord::Base.establish_connection(db_config_postgres)
else
  ActiveRecord::Base.establish_connection(
    adapter: "sqlite3",
    database: ":memory:",
    pool: 50,
    timeout: 1000
  )
end
