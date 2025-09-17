import {
  Wallet,
  Provider,
  WalletUnlocked,
  ContractFactory,
  hexlify,
} from 'fuels';
import fs from 'fs-extra';
import dotenv from 'dotenv';

dotenv.config();

async function main() {
  try {
    const provider = await new Provider(
      'https://testnet.fuel.network/v1/graphql',
    );
    const protocolDeployer = process.env.PROTOCOL_DEPLOYER!;
    const protocolDeployerWallet: WalletUnlocked =
      Wallet.fromMnemonic(protocolDeployer);
    console.log(`Protocol Deployer Address: ${protocolDeployerWallet.address}`);
    console.log(
      `-------------------------------------------------------------`,
    );

    protocolDeployerWallet.connect(provider);

    const bytecode = fs.readFileSync('./out/debug/axios-fuel-core.bin');
    const bytecodeHex = hexlify(bytecode);

    const abi = fs.readJsonSync('./out/debug/axios-fuel-core-abi.json');
    const factory = new ContractFactory(
      bytecodeHex,
      abi,
      protocolDeployerWallet,
    );

    const protocolOwner = process.env.PROTOCOL_OWNER!;
    const protocolOwnerWallet: WalletUnlocked =
      Wallet.fromMnemonic(protocolOwner);
    console.log(`Protocol Onwer Address: ${protocolOwnerWallet.address}`);
    console.log(
      `-------------------------------------------------------------`,
    );

    factory.setConfigurableConstants({
      PROTOCOL_OWNER: { bits: protocolOwnerWallet.address.toB256() },
    });

    const tx = await factory.deploy();
    const response = await tx.waitForResult();

    console.log('Contract Id: ', response.contract.id.toString());
  } catch (error) {
    console.error(error);
  }
}

main();
