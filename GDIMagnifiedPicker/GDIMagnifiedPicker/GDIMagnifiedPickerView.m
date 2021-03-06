//
//  GDIMagnifiedPickerView.m
//  GDIMagnifiedPicker
//
//  Created by Grant Davis on 2/3/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "GDIMagnifiedPickerView.h"
#import "GDIMagnifiedPickerCell.h"

#define kAnimationInterval 1.f/60.f
#define kVelocityFalloffFactor .85f

@interface GDIMagnifiedPickerView() {
    BOOL _isUserDragging;
}

@property (strong,nonatomic) NSMutableArray *currentCells;
@property (strong,nonatomic) NSMutableArray *currentMagnifiedCells;
@property (strong,nonatomic) NSMutableArray *rowPositions;
@property (strong,nonatomic) NSMutableDictionary *dequeuedCells;
@property (strong,nonatomic) UIView *contentView;
@property (strong,nonatomic) UIView *magnificationView;
@property (strong,nonatomic) UIView *magnifiedCellContainerView;
@property (nonatomic) CGFloat rowHeight;
@property (nonatomic) CGFloat magnificationViewHeight;
@property (nonatomic) CGFloat magnification;
@property (nonatomic) NSInteger indexOfFirstRow;
@property (nonatomic) NSInteger indexOfLastRow;
@property (nonatomic) NSUInteger numberOfRows;
@property (nonatomic) CGFloat currentOffset;
@property (nonatomic) CGFloat targetYOffset;
@property (strong,nonatomic) GDITouchProxyView *touchProxyView;
@property (nonatomic) CGPoint lastTouchPoint;
@property (nonatomic) CGFloat velocity;
@property (strong,nonatomic) NSTimer *decelerationTimer;
@property (strong,nonatomic) NSTimer *moveToNearestRowTimer;
@property (strong,nonatomic) NSTimer *velocityFalloffTimer;
@property (nonatomic) CGFloat nearestRowStartValue;
@property (nonatomic) CGFloat nearestRowDelta;
@property (nonatomic) CGFloat nearestRowDuration;
@property (strong,nonatomic) NSDate *nearestRowStartTime;

- (void)setDefaults;
- (void)initDataSourceProperties;

- (void)buildViews;
- (void)buildContentView;
- (void)buildTouchProxyView;
- (void)buildVisibleRows;
- (void)buildMagnificationView;

- (void)updateVisibleRows;

- (void)addTopRow;
- (void)addBottomRow;

- (void)removeTopRow;
- (void)removeBottomRow;

- (void)scrollToNearestRowWithAnimation:(BOOL)animate;
- (void)beginScrollingToNearestRow;
- (void)endScrollingToNearestRow;

- (void)selectRowAtPoint:(CGPoint)point;

- (void)beginDeceleration;
- (void)endDeceleration;
- (void)handleDecelerateTick;

- (void)startVelocityFalloffTimer;
- (void)endVelocityFalloffTimer;
- (void)handleVelocityFalloffTick;

- (void)scrollContentByValue:(CGFloat)value;
- (void)trackTouchPoint:(CGPoint)point inView:(UIView*)view;

- (CGFloat)easeInOutWithCurrentTime:(CGFloat)t start:(CGFloat)b change:(CGFloat)c duration:(CGFloat)d;

- (void)storeDequeuedCell:(UIView *)cell withCellType:(GDIMagnifiedPickerCellType)type;

@end


@implementation GDIMagnifiedPickerView
@synthesize dataSource = _dataSource;
@synthesize delegate = _delegate;
@synthesize friction = _friction;
@synthesize currentIndex = _currentIndex;
@synthesize selectionBackgroundView = _selectionBackgroundView;

@synthesize currentCells = _currentCells;
@synthesize currentMagnifiedCells = _currentMagnifiedCells;
@synthesize rowPositions = _rowPositions;
@synthesize dequeuedCells = _dequeuedCells;
@synthesize contentView = _contentView;
@synthesize magnification = _magnification;
@synthesize magnificationView = _magnificationView;
@synthesize magnifiedCellContainerView = _magnifiedCellContainerView;
@synthesize rowHeight = _rowHeight;
@synthesize magnificationViewHeight = _magnificationViewHeight;
@synthesize indexOfFirstRow = _indexOfFirstRow;
@synthesize indexOfLastRow = _indexOfLastRow;
@synthesize numberOfRows = _numberOfRows;
@synthesize currentOffset = _currentOffset;
@synthesize targetYOffset = _targetYOffset;
@synthesize touchProxyView = _touchProxyView;
@synthesize lastTouchPoint = _lastTouchPoint;
@synthesize velocity = _velocity;
@synthesize decelerationTimer = _decelerationTimer;
@synthesize moveToNearestRowTimer = _moveToNearestRowTimer;
@synthesize velocityFalloffTimer = _velocityFalloffTimer;
@synthesize nearestRowStartValue = _nearestRowStartValue;
@synthesize nearestRowDelta = _nearestRowDelta;
@synthesize nearestRowDuration = _nearestRowDuration;
@synthesize nearestRowStartTime = _nearestRowStartTime;

#pragma mark - Instance Methods

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setDefaults];
        [self buildViews];
    }
    return self;
}


- (void)awakeFromNib
{
    [super awakeFromNib];
    [self setDefaults];
    [self buildViews];
}


- (NSArray *)visibleRows
{
    return [NSArray arrayWithArray:_currentCells];
}

- (void)reloadData
{
    if (_dataSource == nil) {
        return;
    }
    
    // stop all timers
    [self endDeceleration];
    [self endScrollingToNearestRow];
    [self endVelocityFalloffTimer];
    
    if (_dequeuedCells == nil) {
        _dequeuedCells = [NSMutableDictionary dictionary];
    }
    else {
        [_dequeuedCells removeAllObjects];
    }
    
    _currentIndex = -1;
    
    for (UIView *view in _currentCells) {
        [view removeFromSuperview];
    }
    [_currentCells removeAllObjects];
    
    for (UIView *view in _currentMagnifiedCells) {
        [view removeFromSuperview];
    }
    [_currentMagnifiedCells removeAllObjects];
    
    [self initDataSourceProperties];
    [self layoutSubviews];
    [self buildVisibleRows];
    [self scrollToNearestRowWithAnimation:NO];
}

- (void)layoutSubviews
{
    // TODO: Add additional support for adjusting the content size on the fly.    
    _contentView.frame = self.bounds;
    _touchProxyView.frame = self.bounds;
    
    _magnificationView.frame = CGRectMake(0, self.bounds.size.height * .5 - _magnificationViewHeight*.5, self.bounds.size.width, _magnificationViewHeight);

    CGFloat magnificationRowOverlap = _magnificationViewHeight - _rowHeight;
    CGFloat availableHeight = ( self.bounds.size.height - magnificationRowOverlap ) * _magnification;
    CGFloat containerY = _magnificationViewHeight * .5 - availableHeight * .5;
    _magnifiedCellContainerView.frame = CGRectMake(0, containerY, self.bounds.size.width, availableHeight);
}

- (void)setDataSource:(NSObject<GDIMagnifiedPickerViewDataSource> *)dataSource
{
    _dataSource = dataSource;
    if (_dataSource != nil) {
        [self reloadData];
    }
}

- (void)setSelectionBackgroundView:(UIView *)selectionBackgroundView
{
    if (_selectionBackgroundView) {
        [_selectionBackgroundView removeFromSuperview];
    }
    _selectionBackgroundView = selectionBackgroundView;
    
    CGFloat containerY = roundf(self.bounds.size.height * .5 - _selectionBackgroundView.frame.size.height * .5);
    _selectionBackgroundView.frame = CGRectMake(0, containerY, _selectionBackgroundView.frame.size.width, _selectionBackgroundView.frame.size.height);
    [self insertSubview:_selectionBackgroundView belowSubview:_magnificationView];
}


#pragma mark - Initialization Methods

- (void)setDefaults
{
    self.clearsContextBeforeDrawing = NO;
    _friction = .85f;
    _currentOffset = 0;
}


- (void)initDataSourceProperties
{
    _magnification = [_dataSource heightForMagnificationViewInMagnifiedPickerView:self] / [_dataSource heightForRowsInMagnifiedPickerView:self];
    _numberOfRows = [_dataSource numberOfRowsInMagnifiedPickerView:self];
    _rowHeight = [_dataSource heightForRowsInMagnifiedPickerView:self];
    _magnificationViewHeight = [_dataSource heightForMagnificationViewInMagnifiedPickerView:self];
}


#pragma mark - Build Methods

- (void)buildViews
{    
    [self buildContentView];
    [self buildTouchProxyView];
    [self buildMagnificationView];
}

- (void)buildContentView 
{
    _contentView = [[UIView alloc] initWithFrame:self.bounds];
    _contentView.clipsToBounds = YES;
    [self addSubview:_contentView];
}


- (void)buildTouchProxyView
{
    _touchProxyView = [[GDITouchProxyView alloc] initWithFrame:self.bounds];
    _touchProxyView.delegate = self;
    [self addSubview:_touchProxyView];
}


- (void)buildMagnificationView
{
    _magnificationView = [[UIView alloc] initWithFrame:CGRectMake(0, self.bounds.size.height * .5 - _magnificationViewHeight*.5, self.bounds.size.width, _magnificationViewHeight)];
    _magnificationView.userInteractionEnabled = NO;
    _magnificationView.clipsToBounds = YES;
    _magnificationView.opaque = NO;
    [self addSubview:_magnificationView];
    
    CGFloat magnificationRowOverlap = _magnificationViewHeight - _rowHeight;
    CGFloat availableHeight = ( self.bounds.size.height - magnificationRowOverlap ) * _magnification;
    CGFloat containerY = _magnificationViewHeight * .5 - availableHeight * .5;
    _magnifiedCellContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, containerY, self.bounds.size.width, availableHeight)];
    _magnifiedCellContainerView.userInteractionEnabled = NO;
    _magnifiedCellContainerView.opaque = NO;
    [_magnificationView addSubview:_magnifiedCellContainerView];
}


- (void)buildVisibleRows
{
    // build containers for views and their positions
    _currentCells = [NSMutableArray array];
    _currentMagnifiedCells = [NSMutableArray array];
    
    // this position array contains the positions of the views as if they were side by side.
    // when they actually get positioned, the cells nearest the center are distributed to fill
    // the extra space of the view. these values are stored and non-distrubted values so
    // we have an accurate, simple reading of where cells are placed. 
    _rowPositions = [NSMutableArray array];
    
    // zero set all our indicies
    _indexOfFirstRow = 
    _indexOfLastRow = 0;
    
    // here we calculate our positioning for our first view.
    // we only manually build the first view here and then let
    // our 'updateVisibleRows' method do the heavy lifting of
    // filling in the view with rows until it is full.
    CGFloat magnificationRowOverlap = _magnificationViewHeight - _rowHeight;
    CGFloat availableHeight = self.bounds.size.height - magnificationRowOverlap;
    
    // find starting positions
    CGFloat rowY = self.bounds.size.height * .5 - _rowHeight * .5;
    CGFloat posY = availableHeight * .5 - _rowHeight * .5; // value stored in non-distributed position array
    CGFloat magStartY = self.bounds.size.height * .5 - _magnificationViewHeight * .5;
    
    // build the standard sized cells
    GDIMagnifiedPickerCell *cellView = [_dataSource magnifiedPickerView:self cellForRowType:GDIMagnifiedPickerCellTypeStandard atRowIndex:0];
    cellView.cellType = GDIMagnifiedPickerCellTypeStandard;
    cellView.frame = CGRectMake(0, rowY, self.bounds.size.width, _rowHeight);
    
    // store
    [_contentView addSubview:cellView];
    [_currentCells addObject:cellView];
    
    // build the magnified cells
    GDIMagnifiedPickerCell *magnifiedCellView = [_dataSource magnifiedPickerView:self cellForRowType:GDIMagnifiedPickerCellTypeMagnified atRowIndex:0];
    cellView.cellType = GDIMagnifiedPickerCellTypeMagnified;
    magnifiedCellView.frame = CGRectMake(0, magStartY, self.bounds.size.width, _magnificationViewHeight);
    [_magnifiedCellContainerView addSubview:magnifiedCellView];
    [_currentMagnifiedCells addObject:magnifiedCellView];
    
    // store the position of this cell
    [_rowPositions addObject:[NSNumber numberWithFloat:posY]];
    
    // calls the method responsible for checking the stored cells vs the available space
    // and adds and removes rows as necessary to fill the space.
    [self updateVisibleRows];
}


#pragma mark - Cell Reuse


- (GDIMagnifiedPickerCell *)dequeueCellWithType:(GDIMagnifiedPickerCellType)type
{
    GDIMagnifiedPickerCell *dequeuedCell = nil;
    
    NSString *cellTypeKey = [NSString stringWithFormat:@"%d", type];
    dequeuedCell = [_dequeuedCells objectForKey:cellTypeKey];
    
    if (dequeuedCell) {
        [_dequeuedCells removeObjectForKey:cellTypeKey];
    }
    
    return dequeuedCell;
}

- (void)storeDequeuedCell:(UIView *)cell withCellType:(GDIMagnifiedPickerCellType)type
{
    NSString *cellTypeKey = [NSString stringWithFormat:@"%d", type];
    if ([_dequeuedCells objectForKey:cellTypeKey] == nil) {
        [_dequeuedCells setObject:cell forKey:cellTypeKey];
    }
}

#pragma mark - Row Update Methods

- (void)updateVisibleRows
{   
    CGFloat availableHeight = self.bounds.size.height - (_magnificationViewHeight - _rowHeight);
    CGFloat firstRowPos = [(NSNumber *)[_rowPositions objectAtIndex:0] floatValue];
    CGFloat lastRowPos = [(NSNumber *)[_rowPositions lastObject] floatValue];
    
    // remove views that are too far up
    while (firstRowPos + _rowHeight < 0) {
        [self removeTopRow];
        firstRowPos = [(NSNumber *)[_rowPositions objectAtIndex:0] floatValue];
    }
    
    // remove views that are too far down
    while (lastRowPos > availableHeight) {
        [self removeBottomRow];
        lastRowPos = [(NSNumber *)[_rowPositions lastObject] floatValue];
    }
    
    // add views to fill the bottom
    while (lastRowPos + _rowHeight < availableHeight) {
        [self addBottomRow];
        lastRowPos = [(NSNumber *)[_rowPositions lastObject] floatValue];
    }
    
    // add views to fill the top
    while (firstRowPos > 0) {
        [self addTopRow];
        firstRowPos = [(NSNumber *)[_rowPositions objectAtIndex:0] floatValue];
    }
}


- (void)addTopRow
{
    _indexOfFirstRow--;
    if (_indexOfFirstRow < 0) {
        _indexOfFirstRow = _numberOfRows-1;
    }
    
    CGFloat firstRowPos = [(NSNumber *)[_rowPositions objectAtIndex:0] floatValue];
    CGFloat currentY = firstRowPos - _rowHeight;
    [_rowPositions insertObject:[NSNumber numberWithFloat:currentY] atIndex:0];
    
    // build the standard cell
    GDIMagnifiedPickerCell *cellView = [_dataSource magnifiedPickerView:self cellForRowType:GDIMagnifiedPickerCellTypeStandard atRowIndex:_indexOfFirstRow];
    cellView.cellType = GDIMagnifiedPickerCellTypeStandard;
    cellView.frame = CGRectMake(0, currentY, self.frame.size.width, _rowHeight);
    
    [_contentView addSubview:cellView];
    [_currentCells insertObject:cellView atIndex:0];
    
    // build the magnified cell
    GDIMagnifiedPickerCell *magnifiedCellView = [_dataSource magnifiedPickerView:self cellForRowType:GDIMagnifiedPickerCellTypeMagnified atRowIndex:_indexOfFirstRow];
    magnifiedCellView.cellType = GDIMagnifiedPickerCellTypeMagnified;
    magnifiedCellView.frame = CGRectMake(0, firstRowPos - _magnificationViewHeight, self.bounds.size.width, _magnificationViewHeight);
    [_magnifiedCellContainerView addSubview:magnifiedCellView];
    [_currentMagnifiedCells insertObject:magnifiedCellView atIndex:0];
}


- (void)addBottomRow
{
    _indexOfLastRow++;
    if (_indexOfLastRow >= _numberOfRows) {
        _indexOfLastRow = 0;
    }
    
    CGFloat lastRowPos = [(NSNumber *)[_rowPositions lastObject] floatValue];
    CGFloat magnificationRowOverlap = _magnificationViewHeight - _rowHeight;
    CGFloat currentY = lastRowPos + _rowHeight;
    
    [_rowPositions addObject:[NSNumber numberWithFloat:currentY]];
    
    // build the standard cell
    GDIMagnifiedPickerCell *cellView = [_dataSource magnifiedPickerView:self cellForRowType:GDIMagnifiedPickerCellTypeStandard atRowIndex:_indexOfLastRow];
    cellView.cellType = GDIMagnifiedPickerCellTypeStandard;
    cellView.frame = CGRectMake(0, currentY + magnificationRowOverlap, self.frame.size.width, _rowHeight);
    [_contentView addSubview:cellView];
    [_currentCells addObject:cellView];
    
    // build the magnified cell
    GDIMagnifiedPickerCell *magnifiedCellView = [_dataSource magnifiedPickerView:self cellForRowType:GDIMagnifiedPickerCellTypeMagnified atRowIndex:_indexOfLastRow];
    magnifiedCellView.cellType = GDIMagnifiedPickerCellTypeMagnified;
    magnifiedCellView.frame = CGRectMake(0, lastRowPos + _magnificationViewHeight, self.bounds.size.width, _magnificationViewHeight);
    [_magnifiedCellContainerView addSubview:magnifiedCellView];
    [_currentMagnifiedCells addObject:magnifiedCellView];
}


- (void)removeTopRow
{
    UIView *firstRowView = [_currentCells objectAtIndex:0];
    [firstRowView removeFromSuperview];
    [_currentCells removeObject:firstRowView];
    [_rowPositions removeObjectAtIndex:0];
    [self storeDequeuedCell:firstRowView withCellType:GDIMagnifiedPickerCellTypeStandard];
    
    UIView *firstRowMagView = [_currentMagnifiedCells objectAtIndex:0];
    [firstRowMagView removeFromSuperview];
    [_currentMagnifiedCells removeObject:firstRowMagView];
    [self storeDequeuedCell:firstRowMagView withCellType:GDIMagnifiedPickerCellTypeMagnified];
    
    _indexOfFirstRow++;
    if (_indexOfFirstRow > _numberOfRows-1) {
        _indexOfFirstRow = 0;
    }
}


- (void)removeBottomRow
{
    UIView *lastRowView = [_currentCells lastObject];
    [lastRowView removeFromSuperview];
    [_currentCells removeObject:lastRowView];
    [_rowPositions removeLastObject];
    [self storeDequeuedCell:lastRowView withCellType:GDIMagnifiedPickerCellTypeStandard];
    
    UIView *lastRowMagView = [_currentMagnifiedCells lastObject];
    [lastRowMagView removeFromSuperview];
    [_currentMagnifiedCells removeLastObject];
    [self storeDequeuedCell:lastRowMagView withCellType:GDIMagnifiedPickerCellTypeMagnified];
    
    _indexOfLastRow--;
    if (_indexOfLastRow < 0) {
        _indexOfLastRow = _numberOfRows-1;
    }
}

#pragma mark - Touch Tracking


- (void)trackTouchPoint:(CGPoint)point inView:(UIView*)view
{
    CGFloat deltaY = point.y - _lastTouchPoint.y;
    
    [self scrollContentByValue:deltaY];
    
    _velocity = deltaY;
    _lastTouchPoint = point;
}

#pragma mark - Scrolling

- (void)scrollContentByValue:(CGFloat)value
{
    _currentOffset += value;

    // first, we adjust the stored positions of the cells
    for (int i=0; i<_rowPositions.count; i++) {
        NSNumber *pos = [_rowPositions objectAtIndex:i];
        [_rowPositions replaceObjectAtIndex:i withObject:[NSNumber numberWithFloat:pos.floatValue + value]];
    }
    
    CGFloat magnificationRowOverlap = _magnificationViewHeight - _rowHeight;
    CGFloat availableHeight = self.bounds.size.height - magnificationRowOverlap;
    CGFloat centerY = availableHeight * .5;
    CGFloat bottomMagY = centerY - (self.bounds.size.height - availableHeight) * .5;
    
    // reposition the normal sized cells.
    for (int i=0; i<_currentCells.count; i++) {

        UIView *rowView = [_currentCells objectAtIndex:i];
        
        CGFloat dx = 0, dy = 0;
        dy = [(NSNumber *)[_rowPositions objectAtIndex:i] floatValue];
        
        CGFloat rowCenter = dy + _rowHeight*.5;
        CGFloat distanceFromCenter = centerY - rowCenter;
        
        CGFloat offset = 0;

        if (fabsf(distanceFromCenter) <= _rowHeight) {
            CGFloat offsetFactor =  1-(distanceFromCenter / _rowHeight);
            offset = offsetFactor * (magnificationRowOverlap * .5);
        }
        else if (dy >= bottomMagY) {
            offset = magnificationRowOverlap;
        }

        rowView.frame = CGRectMake(dx, dy + offset, rowView.frame.size.width, rowView.frame.size.height);
    }
    
    // reposition the magnified cells
    for (int i=0; i<_currentMagnifiedCells.count; i++) {
        
        UIView *magnifiedRowView = [_currentMagnifiedCells objectAtIndex:i];
        CGFloat dy = [(NSNumber *)[_rowPositions objectAtIndex:i] floatValue] * _magnification;
        magnifiedRowView.frame = CGRectMake(0, dy, magnifiedRowView.frame.size.width, magnifiedRowView.frame.size.height);
    }
    
    [self updateVisibleRows];
}


#pragma mark - Decelerate Methods

- (void)beginDeceleration
{
    [_decelerationTimer invalidate];
    _decelerationTimer = [[NSTimer alloc] initWithFireDate:[NSDate date] interval:kAnimationInterval target:self selector:@selector(handleDecelerateTick) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_decelerationTimer forMode:NSRunLoopCommonModes];
}

- (void)endDeceleration
{
    [_decelerationTimer invalidate];
    _decelerationTimer = nil;
}

- (void)handleDecelerateTick
{
    _velocity *= _friction;
    
    if ( fabsf(_velocity) < .1f) {
        [self endDeceleration];
        [self scrollToNearestRowWithAnimation:YES];
    }
    else {
        [self scrollContentByValue:_velocity];
    }
}

#pragma mark - Nearest Row Scroll Methods


- (void)scrollToNearestRowWithAnimation:(BOOL)animate
{
    // find the row nearest to the center
    NSUInteger indexOfNearestRow = 0;
    CGFloat closestDistance = FLT_MAX;
    CGFloat availableHeight = self.bounds.size.height - (_magnificationViewHeight - _rowHeight);
    CGFloat centerY = availableHeight * .5;
    
    for (int i=0; i<_rowPositions.count; i++) {
        
        CGFloat rowPos = [(NSNumber *)[_rowPositions objectAtIndex:i] floatValue];        
        CGFloat cellCenter = rowPos + _rowHeight * .5;
        CGFloat distance = cellCenter - centerY;
        
        if (fabsf(distance) < fabsf(closestDistance)) {
            closestDistance = distance;
            indexOfNearestRow = i;
        }
    }
    
    _targetYOffset = _currentOffset - closestDistance;
    
    // determine the current index of the selected slice
    NSUInteger newIndex = _indexOfFirstRow + indexOfNearestRow;
    if (newIndex > _numberOfRows-1) {
        newIndex = fmodf(newIndex, _numberOfRows);
    }
    
    if (newIndex != _currentIndex) {
        _currentIndex = newIndex;
        
        if ([_delegate respondsToSelector:@selector(magnifiedPickerView:didSelectRowAtIndex:)]) {
            [_delegate magnifiedPickerView:self didSelectRowAtIndex:_currentIndex];
        }
    }    
    
    if (animate) {
        [self beginScrollingToNearestRow];
    }
    else {
        [self scrollContentByValue:_targetYOffset - _currentOffset];
    }
}


- (void)beginScrollingToNearestRow
{
    CGFloat delta1 = (_targetYOffset - _currentOffset);
    CGFloat delta2 = (_targetYOffset - _currentOffset) + self.bounds.size.height;
    
    if (fabsf(delta1) < fabsf(delta2)) {
        _nearestRowDelta = delta1;
    }
    else {
        _nearestRowDelta = delta2;
    }
    
//    NSLog(@"nearest row delta: %.2f, target y offset: %.2f, currentIndex: %i", _nearestRowDelta, _targetYOffset, _currentIndex);
    
    _nearestRowStartValue = _currentOffset;
    _nearestRowStartTime = [NSDate date];
    _nearestRowDuration = [[_nearestRowStartTime dateByAddingTimeInterval:.666f] timeIntervalSinceDate:_nearestRowStartTime];
    
    [_moveToNearestRowTimer invalidate];
    _moveToNearestRowTimer = [[NSTimer alloc] initWithFireDate:[NSDate date] interval:kAnimationInterval target:self selector:@selector(handleMoveToNearestRowTick) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_moveToNearestRowTimer forMode:NSRunLoopCommonModes];
}


- (void)endScrollingToNearestRow
{
    _nearestRowStartTime = nil;
    [_moveToNearestRowTimer invalidate];
    _moveToNearestRowTimer = nil;
}


- (void)handleMoveToNearestRowTick
{
    // see what our current duration is
    CGFloat currentTime = fabsf([_nearestRowStartTime timeIntervalSinceNow]);
    
    // stop scrolling if we are past our duration
    if (currentTime >= _nearestRowDuration) {
        [self scrollContentByValue:_targetYOffset - _currentOffset];
        [self endScrollingToNearestRow];
    }
    // otherwise, calculate how much we should be scrolling our content by
    else {
        CGFloat dy = [self easeInOutWithCurrentTime:currentTime start:_nearestRowStartValue change:_nearestRowDelta duration:_nearestRowDuration];
        [self scrollContentByValue:dy - _currentOffset];
    }
}


#pragma mark - Velocity Falloff

// velocity falloff is used to decrease the velocity
// between touchesMoved and touchesEnded events.
// this tries to ensure that if a user is moving very slowly,
// the velocity will be reduced to reflect that slow movement.
// otherwise, you can get a jumpy acceleration that occurs
// when you finish your touch

- (void)startVelocityFalloffTimer
{
    [_velocityFalloffTimer invalidate];
    _velocityFalloffTimer = [[NSTimer alloc] initWithFireDate:[NSDate date] interval:kAnimationInterval target:self selector:@selector(handleVelocityFalloffTick) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_velocityFalloffTimer forMode:NSRunLoopCommonModes];
}


- (void)endVelocityFalloffTimer
{
    [_velocityFalloffTimer invalidate];
    _velocityFalloffTimer = nil;
}


- (void)handleVelocityFalloffTick
{
    _velocity *= kVelocityFalloffFactor;
    if (fabsf(_velocity) < 1.f) {
        _velocity = 0.f;
    }
}


#pragma mark - Tap Selection

- (void)selectRowAtPoint:(CGPoint)point
{
    // find the cell that contains the point sent from the touch proxy view
    UIView *selectedCell;
    for (UIView *view in _currentCells) {
        CGPoint locationInView = [view convertPoint:point fromView:_touchProxyView];
        if ([view pointInside:locationInView withEvent:nil]) {
            selectedCell = view;
            break;
        }
    }
    
    // determine how far we have to move to get to center that cell
    NSUInteger indexOfSelectdCell = [_currentCells indexOfObject:selectedCell];
    
    if (indexOfSelectdCell == NSNotFound) {
        [self scrollToNearestRowWithAnimation:YES];
        return;
    }
    
    CGFloat availableHeight = self.bounds.size.height - (_magnificationViewHeight - _rowHeight);
    CGFloat centerY = availableHeight * .5;
    CGFloat rowPos = [(NSNumber *)[_rowPositions objectAtIndex:indexOfSelectdCell] floatValue];        
    CGFloat cellCenter = rowPos + _rowHeight * .5;
    CGFloat distance = cellCenter - centerY;
    _targetYOffset = _currentOffset - distance;
    
    // determine the current index of the selected slice
    NSUInteger newIndex = _indexOfFirstRow + indexOfSelectdCell;
    if (newIndex > _numberOfRows-1) {
        newIndex = fmodf(newIndex, _numberOfRows);
    }
    
    if (newIndex != _currentIndex) {
        _currentIndex = newIndex;
        
        if ([_delegate respondsToSelector:@selector(magnifiedPickerView:didSelectRowAtIndex:)]) {
            [_delegate magnifiedPickerView:self didSelectRowAtIndex:_currentIndex];
        }
    }    
    
    [self beginScrollingToNearestRow];
}


#pragma mark - Gesture View Delegate


- (void)gestureView:(GDITouchProxyView *)gv touchBeganAtPoint:(CGPoint)point
{
    // reset the last point to where we start from.
    _lastTouchPoint = point;
    _velocity = 0;
    _isUserDragging = NO;
    
    [self endDeceleration];
    [self endScrollingToNearestRow];
    [self trackTouchPoint:point inView:gv];
}


- (void)gestureView:(GDITouchProxyView *)gv touchMovedToPoint:(CGPoint)point
{
    _isUserDragging = YES;
    [self trackTouchPoint:point inView:gv];
    [self startVelocityFalloffTimer];
}


- (void)gestureView:(GDITouchProxyView *)gv touchEndedAtPoint:(CGPoint)point
{
    if (_isUserDragging) {
        
        [self endVelocityFalloffTimer];
        
        // if the velocity is low, go to the nearest row
        if (fabsf(_velocity) < 1.f) {
            _velocity = 0.f;
            [self scrollToNearestRowWithAnimation:YES];
        }
        // otherwise, decelerate
        else {
            [self beginDeceleration];
        }
    }
    
    // if we aren't dragging, and we have no velocity, we must be tapping.
    else if (fabsf(_velocity) < 1.f) {
        
        _velocity = 0.f;
        [self selectRowAtPoint:point];
    }
    
    _isUserDragging = NO;
}

/*
 static function easeIn (t:Number, b:Number, c:Number, d:Number):Number {
 return (t==0) ? b : c * Math.pow(2, 10 * (t/d - 1)) + b;
 }
 static function easeOut (t:Number, b:Number, c:Number, d:Number):Number {
 return (t==d) ? b+c : c * (-Math.pow(2, -10 * t/d) + 1) + b;
 }
 static function easeInOut (t:Number, b:Number, c:Number, d:Number):Number {
 if (t==0) return b;
 if (t==d) return b+c;
 if ((t/=d/2) < 1) return c/2 * Math.pow(2, 10 * (t - 1)) + b;
 return c/2 * (-Math.pow(2, -10 * --t) + 2) + b;
 }
 
 Easing equations taken with permission under the BSD license from Robert Penner.
 
 Copyright © 2001 Robert Penner
 All rights reserved.
 */

- (CGFloat)easeInOutWithCurrentTime:(CGFloat)t start:(CGFloat)b change:(CGFloat)c duration:(CGFloat)d
{
    if (t==0) {
        return b;
    }
    if (t==d) {
        return b+c;
    }
    if ((t/=d/2) < 1) {
        return c/2 * powf(2, 10 * (t-1)) + b;
    }
    return c/2 * (-powf(2, -10 * --t) + 2) + b;
}


@end