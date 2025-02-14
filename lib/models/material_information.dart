
class MaterialInformation {
  final String name;
  final int quantity;
  final String price;
  final String currency;

  MaterialInformation({
    required this.name,
    this.quantity = 1,
    required this.price,
     this.currency = 'INR',

  });
}