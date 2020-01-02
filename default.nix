let
	pkgs = import <nixpkgs> {};

	hanalytics = pkgs.fetchFromGitHub {
		owner = "quyse";
		repo = "hanalytics";
		rev = "dbe294c4c1524268683764c3cd3ec947105359c9";
		sha256 = "0wpib53843xggnd70vxxivmv9cd0gqgfpia3v3f81q0vdf8mz61k";
	};

	packages = pkgs.haskellPackages.override {
		# overrides = self: super: with super; {
		overrides = pkgs.haskell.lib.packageSourceOverrides {
			coinmetrics = ./coinmetrics;
			coinmetrics-all-blockchains = ./coinmetrics-all-blockchains;
			coinmetrics-binance = ./coinmetrics-binance;
			coinmetrics-bitcoin = ./coinmetrics-bitcoin;
			coinmetrics-cardano = ./coinmetrics-cardano;
			coinmetrics-cosmos = ./coinmetrics-cosmos;
			coinmetrics-eos = ./coinmetrics-eos;
			coinmetrics-ethereum = ./coinmetrics-ethereum;
			coinmetrics-export = ./coinmetrics-export;
			coinmetrics-grin = ./coinmetrics-grin;
			coinmetrics-iota = ./coinmetrics-iota;
			coinmetrics-monero = ./coinmetrics-monero;
			coinmetrics-monitor = ./coinmetrics-monitor;
			coinmetrics-nem = ./coinmetrics-nem;
			coinmetrics-neo = ./coinmetrics-neo;
			coinmetrics-ripple = ./coinmetrics-ripple;
			coinmetrics-stellar = ./coinmetrics-stellar;
			coinmetrics-storage = ./coinmetrics-storage;
			coinmetrics-tendermint = ./coinmetrics-tendermint;
			coinmetrics-tezos = ./coinmetrics-tezos;
			coinmetrics-tron = ./coinmetrics-tron;
			coinmetrics-waves = ./coinmetrics-waves;

			hanalytics-avro = hanalytics + "/hanalytics-avro";
			hanalytics-base = hanalytics + "/hanalytics-base";
			hanalytics-bigquery = hanalytics + "/hanalytics-bigquery";
			hanalytics-postgres = hanalytics + "/hanalytics-postgres";

			diskhash = "0.0.4.0";
		};
	};

	bins = pkgs.buildEnv {
		name = "haskell-tools";
		paths = with packages; [ coinmetrics-export coinmetrics-monitor ];
	};
in bins
