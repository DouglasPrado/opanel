class CreateServiceObservations < ActiveRecord::Migration[8.0]
  def change
    create_table :service_observations, id: :string, limit: 26 do |t|
      t.references :service, type: :string, limit: 26, null: false, foreign_key: true
      t.string :swarm_service_id, null: true
      t.integer :desired_tasks, null: false, default: 0
      t.integer :running_tasks, null: false, default: 0
      t.integer :healthy_tasks, null: false, default: 0
      t.integer :failed_tasks, null: false, default: 0
      t.string :observed_image_digest, null: true
      t.string :update_status, null: true  # UPDATE_STATUS from Swarm
      t.jsonb :nodes, null: true, default: []  # Array of node IDs where tasks are running
      t.bigint :docker_version_index, null: true  # Version.Index from Swarm to prevent out-of-order updates
      t.timestamptz :observed_at, null: false

      t.timestamps
    end

    # migration-index-review: new table, small initial size, indexes for operational queries
    add_index :service_observations, [:service_id, :observed_at], name: "idx_service_obs_by_service_and_time"
    add_index :service_observations, :observed_at, name: "idx_service_obs_staleness"
  end
end
