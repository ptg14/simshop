# TTSHOP - Application Flow & Architecture

## User Interface Flows

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOME SCREEN                              │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │              SEARCH BAR                               │   │
│  │  Allows searching for products by name               │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │         PROMOTIONAL BANNER                            │   │
│  │  "Đổi PC trong 10 ngày - Không ứng hoàn tiền 100%"  │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │  FEATURED PRODUCTS (Horizontal Scroll)               │   │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                    │   │
│  │  │ PC1 │ │ PC2 │ │ PC3 │ │ ... │                    │   │
│  │  └─────┘ └─────┘ └─────┘ └─────┘                    │   │
│  │  (Products on sale)                                  │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │    CATEGORY SELECTOR (Horizontal Scroll)             │   │
│  │  [All] [PC Gaming] [PC Design] [PC Accessories]     │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │        PRODUCTS GRID (2 columns)                      │   │
│  │  ┌──────────┐      ┌──────────┐                      │   │
│  │  │          │      │          │                      │   │
│  │  │ Product  │      │ Product  │                      │   │
│  │  │ Card 1   │      │ Card 2   │                      │   │
│  │  └──────────┘      └──────────┘                      │   │
│  │  ┌──────────┐      ┌──────────┐                      │   │
│  │  │ Product  │      │ Product  │                      │   │
│  │  │ Card 3   │      │ Card 4   │                      │   │
│  │  └──────────┘      └──────────┘                      │   │
│  │  (Scroll for more)                                   │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
│  🛒 Cart Icon (shows count)                                    │
└─────────────────────────────────────────────────────────────────┘
         ↓                           ↓                    ↓
      [Click]              [Select Category]      [Add to Cart]
         ↓                           ↓                    ↓
  PRODUCT DETAIL          Filter Products      UPDATE CART
```

## Product Detail Screen

```
┌────────────────────────────────────────────┐
│         PRODUCT DETAIL SCREEN              │
│                                            │
│  ◄ [Back Button]                          │
│                                            │
│  ┌────────────────────────────────────┐  │
│  │                                    │  │
│  │      PRODUCT IMAGE                 │  │
│  │      (Large Preview)               │  │
│  │      -15% [Discount Badge]         │  │
│  │                                    │  │
│  └────────────────────────────────────┘  │
│                                            │
│  📌 Category: PC Gaming                    │
│  ⭐ 4.8 (156 reviews)                     │
│                                            │
│  PC TTG GAMING IJ12405                     │
│                                            │
│  💰 23,480,000đ  28,000,000đ (crossed)   │
│     Giảm 15%                               │
│                                            │
│  ⚠️ Còn 12 sản phẩm                        │
│                                            │
│  📝 Mô tả sản phẩm                         │
│  High-performance gaming PC with latest... │
│                                            │
│  🔧 Thông số kỹ thuật                      │
│  ✓ Intel i9-13900K                        │
│  ✓ RTX 4080                                │
│  ✓ 32GB RAM                                │
│  ✓ 2TB SSD                                 │
│                                            │
│  📊 Số lượng                                │
│  [−] 1 [+]  (Tối đa: 12)                 │
│                                            │
│  ┌────────────────────────────────────┐  │
│  │  THÊM VÀO GIỎ HÀNG (Orange Button) │  │
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │  MUA NGAY (Outlined Button)        │  │
│  └────────────────────────────────────┘  │
└────────────────────────────────────────────┘
           ↓
      [Add to Cart]
           ↓
       CART UPDATED
```

## Shopping Cart Screen

```
┌────────────────────────────────────────────┐
│         SHOPPING CART SCREEN               │
│                                            │
│  ┌────────────────────────────────────┐  │
│  │ CART ITEM 1                        │  │
│  │  ┌─────────┐  Product Name        │  │
│  │  │ Image   │  23,480,000đ/cái    │  │
│  │  │         │  [−] 1 [+]           │  │
│  │  │         │  Total: 23,480,000đ  │  │
│  │  │         │                  [🗑️] │  │
│  │  └─────────┘                      │  │
│  └────────────────────────────────────┘  │
│                                            │
│  ┌────────────────────────────────────┐  │
│  │ CART ITEM 2                        │  │
│  │  ┌─────────┐  Product Name        │  │
│  │  │ Image   │  2,500,000đ/cái     │  │
│  │  │         │  [−] 2 [+]           │  │
│  │  │         │  Total: 5,000,000đ   │  │
│  │  │         │                  [🗑️] │  │
│  │  └─────────┘                      │  │
│  └────────────────────────────────────┘  │
│                                            │
│  ────────────────────────────────────────│
│  📋 ORDER SUMMARY                         │
│  Tạm tính:              28,480,000đ      │
│  Thuế (10%):             2,848,000đ      │
│  Vận chuyển:                    0đ       │
│  ────────────────────────────────────────│
│  TỔNG CỘNG:             31,328,000đ      │
│  ────────────────────────────────────────│
│                                            │
│  ┌────────────────────────────────────┐  │
│  │   TIẾN HÀNH THANH TOÁN (Orange)   │  │
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │   TIẾP TỤC MUA SẮM (Outlined)     │  │
│  └────────────────────────────────────┘  │
└────────────────────────────────────────────┘
```

## Data Flow Architecture

```
                    ┌─────────────────────────┐
                    │    HOME SCREEN          │
                    │    (View Layer)         │
                    └────────┬────────────────┘
                             │
                    ┌────────▼────────────┐
                    │  HOME VIEW MODEL    │
                    │  ▪ products        │
                    │  ▪ categories      │
                    │  ▪ isLoading       │
                    │  ▪ Methods:        │
                    │    - loadProducts()│
                    │    - search()      │
                    │    - filter()      │
                    └────────┬───────────┘
                             │
                    ┌────────▼──────────────┐
                    │  PRODUCT SERVICE     │
                    │  (Data Layer)        │
                    │  ▪ IProductService  │
                    │  ▪ MockProductService
                    │  Methods:           │
                    │  - getAllProducts() │
                    │  - searchProducts() │
                    │  - getCategories()  │
                    └────────┬────────────┘
                             │
                    ┌────────▼────────────┐
                    │   MODELS            │
                    │  ▪ Product         │
                    │  ▪ CartItem        │
                    └────────────────────┘


                    ┌─────────────────────────┐
                    │    CART SCREEN          │
                    │    (View Layer)         │
                    └────────┬────────────────┘
                             │
                    ┌────────▼────────────┐
                    │  CART VIEW MODEL    │
                    │  ▪ items           │
                    │  ▪ totalPrice      │
                    │  Methods:          │
                    │  - addToCart()     │
                    │  - removeFromCart()│
                    │  - updateQty()     │
                    └────────────────────┘
```

## Component Hierarchy

```
MyApp
├── MaterialApp
│   ├── Theme Setup
│   ├── Route Configuration
│   └── Providers
│       ├── HomeViewModel
│       └── CartViewModel
│
├── HomeScreen
│   ├── AppBar
│   │   ├── Title (TTSHOP)
│   │   └── Shopping Cart Icon
│   └── Body
│       ├── SearchBar
│       ├── PromoBanner
│       ├── SectionTitle
│       ├── FeaturedProductsList
│       │   └── ProductCard (Multiple)
│       │       ├── Product Image
│       │       ├── Discount Badge
│       │       ├── Stock Badge
│       │       ├── Product Name
│       │       ├── Category
│       │       ├── Rating
│       │       ├── Price
│       │       └── Add to Cart Button
│       ├── CategorySelector
│       │   └── Category Buttons
│       └── ProductsGrid
│           └── ProductCard (Multiple)
│
├── ProductDetailScreen
│   ├── AppBar
│   │   └── Back Button
│   ├── Image Section
│   │   ├── Product Image
│   │   └── Discount Badge
│   └── Details Section
│       ├── Category Badge
│       ├── Rating
│       ├── Product Name
│       ├── Price Section
│       ├── Stock Info
│       ├── Description
│       ├── Specifications List
│       ├── Quantity Selector
│       ├── Add to Cart Button
│       └── Buy Now Button
│
└── CartScreen
    ├── AppBar
    ├── CartItemsList
    │   └── CartItemTile (Multiple)
    │       ├── Image
    │       ├── Product Details
    │       └── Quantity Controls
    └── OrderSummary
        ├── Subtotal
        ├── Tax
        ├── Shipping
        ├── Total
        └── Checkout Button
```

## State Management Flow

```
User Action
    ↓
View calls ViewModel method
    ↓
ViewModel updates state
    ↓
ViewModel calls notifyListeners()
    ↓
Consumer catches notification
    ↓
Widget rebuilds with new state
    ↓
UI displays updated data


Example: Adding Product to Cart
────────────────────────────────
1. User clicks "Add to Cart" button
        ↓
2. ProductCard calls:
   onAddToCart() → context.read<CartViewModel>().addToCart(product)
        ↓
3. CartViewModel.addToCart():
   - Checks if product exists in cart
   - Either increments quantity or adds new item
   - Calls notifyListeners()
        ↓
4. Consumer<CartViewModel> receives notification
        ↓
5. Widget rebuilds
        ↓
6. Cart count updates in AppBar
   Snackbar shows confirmation
```

## Network Call Flow (When API Integration is Added)

```
User Interaction
    ↓
ViewModel method called
    ↓
Service.method() called (HTTP request)
    ↓
┌─────────────────────────────┐
│  Network Request            │
│  GET /api/products          │
│  GET /api/products/search   │
│  GET /api/categories        │
└─────────────────────────────┘
    ↓
Response Received
    ↓
Parse JSON response
    ↓
Create Model instances
    ↓
Update ViewModel state
    ↓
notifyListeners()
    ↓
UI Rebuilds
```

## Navigation Flow

```
HomeScreen
    ↓ [Click Product Card]
    ├─→ ProductDetailScreen
    │       ↓ [Add to Cart or Back]
    │       └─→ HomeScreen
    │
    ↓ [Click Cart Icon]
    └─→ CartScreen
            ↓ [Continue Shopping]
            └─→ HomeScreen
```

This architecture ensures:
- ✅ Separation of Concerns
- ✅ Testability
- ✅ Reusability
- ✅ Maintainability
- ✅ Scalability
