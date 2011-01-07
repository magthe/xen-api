let create ~__context ~username ~pword ~other_config =
	let ref = Ref.make () in
	let uuid = Uuid.to_string (Uuid.make_uuid ()) in
	Db.Credential.create ~__context ~ref ~uuid ~username ~pword ~other_config;
	ref

let destroy ~__context ~self = Db.Credential.destroy ~__context ~self
