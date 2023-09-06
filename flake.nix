{
  description = "Configuration of ArgoCD-based Kubernetes Environments.";

  inputs.nixhelm.url = "github:farcaller/nixhelm";

  outputs = { self, nixpkgs, nixhelm, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      kubeConfig = { modules, specialArgs ? { } }: lib.evalModules {
        modules = [
          ./lib/apps.nix
          ./lib/clusters.nix
          ./lib/resources.nix
        ] ++ modules;
        specialArgs = { inherit pkgs; } // specialArgs;
      };
    in
    {
      kubeConfig = { modules, specialArgs } @ args:
        let
          generatedConfig = (kubeConfig args).config;
        in
        pkgs.lib.pipe [
          (builtins.attrValues generatedConfig.resources.appProjects)
          (builtins.attrValues generatedConfig.resources.applications)
        ] [
          lib.flatten
          (objs: {
            apiVersion = "v1";
            kind = "List";
            items = objs;
          })
          ((pkgs.formats.yaml { }).generate "manifest.yaml")
        ];
    });
}
