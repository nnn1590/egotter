namespace :not_found_users do
  desc 'update uid'
  task update_uid: :environment do
    NotFoundUser.update_uid_batch
  end
end
